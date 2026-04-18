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

const makeActiveMetrics = () => {
	const registry = new Registry();
	collectDefaultMetrics({ register: registry });

	const httpRequestsTotal = new Counter({
		name: "corpus_http_requests_total",
		help: "Total number of HTTP requests",
		labelNames: ["method", "path", "status"],
		registers: [registry],
	});

	const httpRequestDurationSeconds = new Histogram({
		name: "corpus_http_request_duration_seconds",
		help: "HTTP request duration in seconds",
		labelNames: ["method", "path"],
		buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
		registers: [registry],
	});

	const syncRunsTotal = new Counter({
		name: "corpus_sync_runs_total",
		help: "Total number of sync runs",
		labelNames: ["user", "source", "result"],
		registers: [registry],
	});

	const syncScrobblesAddedTotal = new Counter({
		name: "corpus_sync_scrobbles_added_total",
		help: "Total scrobbles added during syncs",
		labelNames: ["user", "source"],
		registers: [registry],
	});

	const syncLastSuccessSeconds = new Gauge({
		name: "corpus_sync_last_success_seconds",
		help: "Unix timestamp of last successful sync run",
		labelNames: ["user", "source"],
		registers: [registry],
	});

	const enrichmentFetchesTotal = new Counter({
		name: "corpus_enrichment_fetches_total",
		help: "Total metadata enrichment fetches by user, source, and result",
		labelNames: ["user", "source", "result"],
		registers: [registry],
	});

	const enrichmentQueueSize = new Gauge({
		name: "corpus_enrichment_queue_size",
		help: "Number of releases pending metadata enrichment per user",
		labelNames: ["user", "type"],
		registers: [registry],
	});

	const coverRequestsTotal = new Counter({
		name: "corpus_cover_requests_total",
		help: "Total cover art requests by user, source, and result",
		labelNames: ["user", "source", "result"],
		registers: [registry],
	});

	const dbBackupRunsTotal = new Counter({
		name: "corpus_db_backup_runs_total",
		help: "Total database backup runs",
		labelNames: ["user", "result"],
		registers: [registry],
	});

	const dbBackupLastSuccessSeconds = new Gauge({
		name: "corpus_db_backup_last_success_seconds",
		help: "Unix timestamp of last successful database backup",
		labelNames: ["user"],
		registers: [registry],
	});

	return {
		getMetrics: () => registry.metrics(),
		contentType: registry.contentType,
		recordHttpRequest: (method, path, status, durationMs) => {
			httpRequestsTotal.inc({ method, path, status: String(status) });
			httpRequestDurationSeconds.observe({ method, path }, durationMs / 1000);
		},
		incSyncRuns: (user, source, result) => syncRunsTotal.inc({ user, source, result }),
		incSyncScrobbles: (user, source, count) => syncScrobblesAddedTotal.inc({ user, source }, count),
		setSyncLastSuccess: (user, source) => syncLastSuccessSeconds.setToCurrentTime({ user, source }),
		incEnrichmentFetch: (user, source, result) => enrichmentFetchesTotal.inc({ user, source, result }),
		setEnrichmentQueueSize: (user, type, size) => enrichmentQueueSize.set({ user, type }, size),
		incCoverRequest: (user, source, result) => coverRequestsTotal.inc({ user, source, result }),
		incDbBackupRun: (user, result) => dbBackupRunsTotal.inc({ user, result }),
		setDbBackupLastSuccess: (user) => dbBackupLastSuccessSeconds.setToCurrentTime({ user }),
	};
};

const noOp = () => {};

const makeNoOpMetrics = () => ({
	getMetrics: () => Promise.resolve(""),
	contentType: "text/plain; version=0.0.4; charset=utf-8",
	recordHttpRequest: noOp,
	incSyncRuns: noOp,
	incSyncScrobbles: noOp,
	setSyncLastSuccess: noOp,
	incEnrichmentFetch: noOp,
	setEnrichmentQueueSize: noOp,
	incCoverRequest: noOp,
	incDbBackupRun: noOp,
	setDbBackupLastSuccess: noOp,
});

const activeMetrics =
	process.env.METRICS_ENABLED === "true" ? makeActiveMetrics() : makeNoOpMetrics();

// ---------------------------------------------------------------------------
// OpenTelemetry — only active when OTEL_EXPORTER_OTLP_ENDPOINT is set
// ---------------------------------------------------------------------------

const makeTracer = () => {
	if (!process.env.OTEL_EXPORTER_OTLP_ENDPOINT) return null;
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
	const tracer = trace.getTracer(
		process.env.OTEL_SERVICE_NAME || "corpus",
		process.env.npm_package_version,
	);
	process.on("SIGTERM", () => sdk.shutdown().finally(() => process.exit(0)));
	return tracer;
};

const tracer = makeTracer();

const startHttpSpan = (method, path, headers) => {
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
};

const endHttpSpan = (span, statusCode) => {
	if (!span) return;
	span.setAttribute("http.status_code", statusCode);
	span.setStatus({
		code: statusCode >= 500 ? SpanStatusCode.ERROR : SpanStatusCode.OK,
	});
	span.end();
};

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

export const getMetricsImpl = (onSuccess) => (onError) => () => {
	activeMetrics.getMetrics().then(
		(s) => onSuccess(s)(),
		(err) => onError(err.message)(),
	);
};

export const getContentType = () => activeMetrics.contentType;

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
			activeMetrics.recordHttpRequest(method, path, status, durationMs);
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
	activeMetrics.incSyncRuns(user, source, result);
};

export const incSyncScrobbles = (user) => (source) => (count) => () => {
	activeMetrics.incSyncScrobbles(user, source, count);
};

export const setSyncLastSuccess = (user) => (source) => () => {
	activeMetrics.setSyncLastSuccess(user, source);
};

export const incEnrichmentFetch = (user) => (source) => (result) => () => {
	activeMetrics.incEnrichmentFetch(user, source, result);
};

export const setEnrichmentQueueSize = (user) => (type) => (size) => () => {
	activeMetrics.setEnrichmentQueueSize(user, type, size);
};

export const incCoverRequest = (user) => (source) => (result) => () => {
	activeMetrics.incCoverRequest(user, source, result);
};

export const incDbBackupRun = (user) => (result) => () => {
	activeMetrics.incDbBackupRun(user, result);
};

export const setDbBackupLastSuccess = (user) => () => {
	activeMetrics.setDbBackupLastSuccess(user);
};
