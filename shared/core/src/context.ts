import { AsyncLocalStorage } from 'node:async_hooks';

export interface RequestContext {
  requestId?: string;
  correlationId?: string;
  userId?: string | number;
  service?: string;
  [key: string]: unknown;
}

const requestContextStorage = new AsyncLocalStorage<RequestContext>();

export function withRequestContext<T>(context: RequestContext, callback: () => T): T {
  const currentContext = requestContextStorage.getStore() ?? {};
  return requestContextStorage.run({ ...currentContext, ...context }, callback);
}

export function getRequestContext(): RequestContext {
  return requestContextStorage.getStore() ?? {};
}

export function setRequestContextValue(key: string, value: unknown): void {
  const store = requestContextStorage.getStore();
  if (store) {
    store[key] = value;
  }
}

export function clearRequestContext(): void {
  requestContextStorage.disable();
}
