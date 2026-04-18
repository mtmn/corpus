import {
	Registry,
	Counter,
	Gauge,
	Histogram,
	collectDefaultMetrics,
} from "prom-client";
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { HttpInstrumentation } from "@opentelemetry/instrumentation-http";
import { UndiciInstrumentation } from "@opentelemetry/instrumentation-undici";
import {
	trace,
	context,
	propagation,
	SpanKind,
	SpanStatusCode,
} from "@opentelemetry/api";

// ---------------------------------------------------------------------------
// Prometheus metrics — only active when METRICS_ENABLED=true
// ---------------------------------------------------------------------------

const metricsEnabled = process.env.METRICS_ENABLED === "true";

let registry = null;
let httpRequestsTotal = null;
let httpRequestDurationSeconds = null;
let syncRunsTotal = null;
let syncScrobblesAddedTotal = null;
let syncLastSuccessSeconds = null;
let enrichmentFetchesTotal = null;
let enrichmentQueueSize = null;
let coverRequestsTotal = null;
let dbBackupRunsTotal = null;
let dbBackupLastSuccessSeconds = null;

if (metricsEnabled) {
	registry = new Registry();
	collectDefaultMetrics({ register: registry });

	httpRequestsTotal = new Counter({
		name: "corpus_http_requests_total",
		help: "Total number of HTTP requests",
		labelNames: ["method", "path", "status"],
		registers: [registry],
	});

	httpRequestDurationSeconds = new Histogram({
		name: "corpus_http_request_duration_seconds",
		help: "HTTP request duration in seconds",
		labelNames: ["method", "path"],
		buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
		registers: [registry],
	});

	syncRunsTotal = new Counter({
		name: "corpus_sync_runs_total",
		help: "Total number of sync runs",
		labelNames: ["user", "source", "result"],
		registers: [registry],
	});

	syncScrobblesAddedTotal = new Counter({
		name: "corpus_sync_scrobbles_added_total",
		help: "Total scrobbles added during syncs",
		labelNames: ["user", "source"],
		registers: [registry],
	});

	syncLastSuccessSeconds = new Gauge({
		name: "corpus_sync_last_success_seconds",
		help: "Unix timestamp of last successful sync run",
		labelNames: ["user", "source"],
		registers: [registry],
	});

	enrichmentFetchesTotal = new Counter({
		name: "corpus_enrichment_fetches_total",
		help: "Total metadata enrichment fetches by user, source, and result",
		labelNames: ["user", "source", "result"],
		registers: [registry],
	});

	enrichmentQueueSize = new Gauge({
		name: "corpus_enrichment_queue_size",
		help: "Number of releases pending metadata enrichment per user",
		labelNames: ["user", "type"],
		registers: [registry],
	});

	coverRequestsTotal = new Counter({
		name: "corpus_cover_requests_total",
		help: "Total cover art requests by user, source, and result",
		labelNames: ["user", "source", "result"],
		registers: [registry],
	});

	dbBackupRunsTotal = new Counter({
		name: "corpus_db_backup_runs_total",
		help: "Total database backup runs",
		labelNames: ["user", "result"],
		registers: [registry],
	});

	dbBackupLastSuccessSeconds = new Gauge({
		name: "corpus_db_backup_last_success_seconds",
		help: "Unix timestamp of last successful database backup",
		labelNames: ["user"],
		registers: [registry],
	});
}

// ---------------------------------------------------------------------------
// OpenTelemetry — only active when OTEL_EXPORTER_OTLP_ENDPOINT is set
// ---------------------------------------------------------------------------

let tracer = null;

if (process.env.OTEL_EXPORTER_OTLP_ENDPOINT) {
	const sdk = new NodeSDK({
		traceExporter: new OTLPTraceExporter(),
		instrumentations: [
			new HttpInstrumentation({
				// Incoming requests are traced manually via wrapRequest below
				ignoreIncomingRequestHook: () => true,
			}),
			new UndiciInstrumentation(),
		],
	});
	sdk.start();
	tracer = trace.getTracer(
		process.env.OTEL_SERVICE_NAME || "corpus",
		process.env.npm_package_version,
	);
	process.on("SIGTERM", () => sdk.shutdown().finally(() => process.exit(0)));
}

function startHttpSpan(method, path, headers) {
	if (!tracer) return null;
	const parentCtx = propagation.extract(context.active(), headers);
	return tracer.startSpan(
		`${method} ${path}`,
		{
			kind: SpanKind.SERVER,
			attributes: {
				"http.method": method,
				"http.target": path,
			},
		},
		parentCtx,
	);
}

function endHttpSpan(span, statusCode) {
	if (!span) return;
	span.setAttribute("http.status_code", statusCode);
	span.setStatus({
		code: statusCode >= 500 ? SpanStatusCode.ERROR : SpanStatusCode.OK,
	});
	span.end();
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

export const getMetricsImpl = (onSuccess) => (onError) => () => {
	if (!registry) {
		onSuccess("")();
		return;
	}
	registry.metrics().then(
		(s) => onSuccess(s)(),
		(err) => onError(err.message)(),
	);
};

export const getContentType = () =>
	registry ? registry.contentType : "text/plain; version=0.0.4; charset=utf-8";

// Runs `handler` inside the active context of a server span so that any
// outbound HTTP/fetch calls made during handling automatically become child
// spans. Attaches a 'finish' listener to record metrics and end the span.
// logFn: String -> Effect Unit — structured logger called on completion.
// req: Node IncomingMessage — used to extract W3C trace-context headers.
export const wrapRequest =
	(method) => (path) => (logFn) => (req) => (res) => (handler) => () => {
		const startMs = Date.now();
		const span = startHttpSpan(method, path, req.headers || {});
		res.once("finish", () => {
			const durationMs = Date.now() - startMs;
			const status = res.statusCode || 0;
			if (httpRequestsTotal) httpRequestsTotal.inc({ method, path, status: String(status) });
			if (httpRequestDurationSeconds) httpRequestDurationSeconds.observe({ method, path }, durationMs / 1000);
			endHttpSpan(span, status);
			logFn(`${method} ${path} ${status} ${durationMs}ms`)();
		});
		if (span) {
			const ctx = trace.setSpan(context.active(), span);
			context.with(ctx, () => handler());
		} else {
			handler();
		}
	};

export const incSyncRuns = (user) => (source) => (result) => () => {
	if (syncRunsTotal) syncRunsTotal.inc({ user, source, result });
};

export const incSyncScrobbles = (user) => (source) => (count) => () => {
	if (syncScrobblesAddedTotal)
		syncScrobblesAddedTotal.inc({ user, source }, count);
};

export const setSyncLastSuccess = (user) => (source) => () => {
	if (syncLastSuccessSeconds)
		syncLastSuccessSeconds.setToCurrentTime({ user, source });
};

export const incEnrichmentFetch = (user) => (source) => (result) => () => {
	if (enrichmentFetchesTotal)
		enrichmentFetchesTotal.inc({ user, source, result });
};

export const setEnrichmentQueueSize = (user) => (type) => (size) => () => {
	if (enrichmentQueueSize) enrichmentQueueSize.set({ user, type }, size);
};

export const incCoverRequest = (user) => (source) => (result) => () => {
	if (coverRequestsTotal) coverRequestsTotal.inc({ user, source, result });
};

export const incDbBackupRun = (user) => (result) => () => {
	if (dbBackupRunsTotal) dbBackupRunsTotal.inc({ user, result });
};

export const setDbBackupLastSuccess = (user) => () => {
	if (dbBackupLastSuccessSeconds)
		dbBackupLastSuccessSeconds.setToCurrentTime({ user });
};
