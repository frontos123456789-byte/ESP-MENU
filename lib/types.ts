export type Risk = "low" | "medium" | "high";
export type Status = "ok" | "unsupported" | "error" | "unknown";
export type Value =
  string | number | boolean | null | Value[] | { [key: string]: Value };
export interface Field {
  key: string;
  label: string;
  value: Value;
  risk: Risk;
  note: string;
  status: Status;
}
export interface Section {
  id: string;
  title: string;
  description: string;
  fields: Field[];
  state: "loading" | "done";
}
export type Collector = (signal: AbortSignal) => Promise<Field[]>;
export interface Whoami {
  ip: string | null;
  ipVersion: string | null;
  geo: Record<string, string | null>;
  headers: Record<string, string>;
  protocol: string;
  httpVersion: null;
  enrichment: Record<string, Value> | null;
  enrichmentError: string | null;
}
export interface Finding {
  id: string;
  title: string;
  level: "green" | "yellow" | "red" | "unknown";
  detail: string;
  recommendation?: string;
}
