import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { NodeSDK } from '@opentelemetry/sdk-node';

import { config, isDevelopment, isTest } from './config.js';
import { logger } from './logger.js';

let sdk: NodeSDK | undefined;
let tracingStarted = false;

function buildTraceExporterUrl(endpoint: string): string {
  const normalized = endpoint.endsWith('/') ? endpoint.slice(0, -1) : endpoint;
  return normalized.endsWith('/v1/traces') ? normalized : `${normalized}/v1/traces`;
}

export function startTracing(): void {
  if (tracingStarted || isTest || !config.OTEL_EXPORTER_OTLP_ENDPOINT) {
    return;
  }

  if (isDevelopment) {
    diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.ERROR);
  }

  sdk = new NodeSDK({
    traceExporter: new OTLPTraceExporter({
      url: buildTraceExporterUrl(config.OTEL_EXPORTER_OTLP_ENDPOINT),
    }),
    instrumentations: [getNodeAutoInstrumentations()],
  });

  sdk.start();
  tracingStarted = true;
  logger.info({ exporter: config.OTEL_EXPORTER_OTLP_ENDPOINT }, 'OpenTelemetry tracing enabled');
}

export async function stopTracing(): Promise<void> {
  if (!sdk || !tracingStarted) {
    return;
  }

  await sdk.shutdown();
  tracingStarted = false;
  logger.info('OpenTelemetry tracing stopped');
}
