import { AsyncLocalStorage } from 'node:async_hooks';

export interface RequestStore {
  requestId: string;
}

export const requestStore = new AsyncLocalStorage<RequestStore>();

export function getRequestId(): string | undefined {
  return requestStore.getStore()?.requestId;
}
