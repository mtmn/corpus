import {
	Registry,
	Counter,
	Gauge,
	Histogram,
	collectDefaultMetrics,
} from "prom-client";
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import {
	trace,
	context,
	propagation,
	SpanKind,
	SpanStatusCode,
} from "@opentelemetry/api";

// ---------------------------------------------------------------------------
// Prometheus metrics
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// OpenTelemetry — only active when OTEL_EXPORTER_OTLP_ENDPOINT is set
// ---------------------------------------------------------------------------

let tracer = null;

if (process.env.OTEL_EXPORTER_OTLP_ENDPOINT) {
	const sdk = new NodeSDK({
		traceExporter: new OTLPTraceExporter(),
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
	registry.metrics().then(
		(s) => onSuccess(s)(),
		(err) => onError(err.message)(),
	);
};

export const getContentType = () => registry.contentType;

// Attaches a 'finish' listener to `res` so that, once the response is fully
// written, the request count, latency histogram, and OTEL span are updated.
// logFn: String -> Effect Unit — the structured logger to call on completion.
// req: Node IncomingMessage — used to extract W3C trace-context headers.
export const observeHttpRequest =
	(method) => (path) => (logFn) => (req) => (res) => () => {
		const startMs = Date.now();
		const span = startHttpSpan(method, path, req.headers || {});
		res.once("finish", () => {
			const durationMs = Date.now() - startMs;
			const durationSecs = durationMs / 1000;
			const status = res.statusCode || 0;
			httpRequestsTotal.inc({ method, path, status: String(status) });
			httpRequestDurationSeconds.observe({ method, path }, durationSecs);
			endHttpSpan(span, status);
			logFn(`${method} ${path} ${status} ${durationMs}ms`)();
		});
	};

export const incSyncRuns = (user) => (source) => (result) => () =>
	syncRunsTotal.inc({ user, source, result });

export const incSyncScrobbles = (user) => (source) => (count) => () =>
	syncScrobblesAddedTotal.inc({ user, source }, count);

export const setSyncLastSuccess = (user) => (source) => () =>
	syncLastSuccessSeconds.setToCurrentTime({ user, source });

export const incEnrichmentFetch = (user) => (source) => (result) => () =>
	enrichmentFetchesTotal.inc({ user, source, result });

export const setEnrichmentQueueSize = (user) => (type) => (size) => () =>
	enrichmentQueueSize.set({ user, type }, size);

export const incCoverRequest = (user) => (source) => (result) => () =>
	coverRequestsTotal.inc({ user, source, result });

export const incDbBackupRun = (user) => (result) => () =>
	dbBackupRunsTotal.inc({ user, result });

export const setDbBackupLastSuccess = (user) => () =>
	dbBackupLastSuccessSeconds.setToCurrentTime({ user });
