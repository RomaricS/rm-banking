// Pay period math (mirrored in AkweKit/PayPeriod.swift — keep both in sync).
import type { PayFrequency, PaySchedule } from "./types.ts";

export interface Period { start: string; end: string } // inclusive, YYYY-MM-DD

const DAY = 86_400_000;
const toUTC = (d: string) => Date.parse(d + "T00:00:00Z");
const fmt = (ms: number) => new Date(ms).toISOString().slice(0, 10);
const addDays = (d: string, n: number) => fmt(toUTC(d) + n * DAY);
const daysInMonth = (y: number, m: number) => new Date(Date.UTC(y, m + 1, 0)).getUTCDate();

function clampDay(y: number, m: number, day: number): string {
  const yy = y + Math.floor(m / 12);
  const mm = ((m % 12) + 12) % 12;
  const dd = Math.min(day, daysInMonth(yy, mm));
  return fmt(Date.UTC(yy, mm, dd));
}

export function periodFor(date: string, s: PaySchedule): Period {
  switch (s.frequency) {
    case "weekly":
    case "biweekly": {
      const len = s.frequency === "weekly" ? 7 : 14;
      const diff = Math.floor((toUTC(date) - toUTC(s.anchorDate)) / DAY);
      const k = Math.floor(diff / len);
      const start = addDays(s.anchorDate, k * len);
      return { start, end: addDays(start, len - 1) };
    }
    case "semimonthly": {
      const days = [...(s.semimonthlyDays.length === 2 ? s.semimonthlyDays : [1, 15])].sort((a, b) => a - b);
      const d = new Date(toUTC(date));
      const y = d.getUTCFullYear(), m = d.getUTCMonth();
      const candidates = [
        clampDay(y, m - 1, days[1]), clampDay(y, m, days[0]), clampDay(y, m, days[1]), clampDay(y, m + 1, days[0]),
      ];
      for (let i = candidates.length - 2; i >= 0; i--) {
        if (candidates[i] <= date) return { start: candidates[i], end: addDays(candidates[i + 1], -1) };
      }
      return { start: candidates[0], end: addDays(candidates[1], -1) };
    }
    case "monthly": {
      const anchorDay = new Date(toUTC(s.anchorDate)).getUTCDate();
      const d = new Date(toUTC(date));
      const y = d.getUTCFullYear(), m = d.getUTCMonth();
      let start = clampDay(y, m, anchorDay);
      if (start > date) start = clampDay(y, m - 1, anchorDay);
      const sd = new Date(toUTC(start));
      const next = clampDay(sd.getUTCFullYear(), sd.getUTCMonth() + 1, anchorDay);
      return { start, end: addDays(next, -1) };
    }
  }
}

export function monthFor(date: string): Period {
  const d = new Date(toUTC(date));
  const start = fmt(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
  const end = fmt(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0));
  return { start, end };
}

/**
 * Detect the pay schedule from income deposits (dates of the biggest recurring inflow).
 * Returns null if fewer than 3 paychecks are found.
 */
export function detectSchedule(paydays: string[]): (PaySchedule & { frequency: PayFrequency }) | null {
  const ds = [...new Set(paydays)].sort();
  if (ds.length < 3) return null;
  const gaps: number[] = [];
  for (let i = 1; i < ds.length; i++) gaps.push(Math.round((toUTC(ds[i]) - toUTC(ds[i - 1])) / DAY));
  const median = [...gaps].sort((a, b) => a - b)[Math.floor(gaps.length / 2)];
  const last = ds[ds.length - 1];
  if (median >= 6 && median <= 8) return { frequency: "weekly", anchorDate: last, semimonthlyDays: [1, 15] };
  if (median >= 26 && median <= 33) return { frequency: "monthly", anchorDate: last, semimonthlyDays: [1, 15] };
  if (median >= 12 && median <= 17) {
    // Semi-monthly paydays stick to two days of the month (± weekend shifts); bi-weekly ones drift.
    const days = ds.map((d) => new Date(toUTC(d)).getUTCDate()).sort((a, b) => a - b);
    const clusters: number[][] = [];
    for (const d of days) {
      const c = clusters.find((cl) => Math.abs(cl[0] - d) <= 3);
      if (c) c.push(d); else clusters.push([d]);
    }
    const exactTwoWeeks = gaps.filter((g) => g === 14).length >= Math.ceil(gaps.length * 0.6);
    if (!exactTwoWeeks && clusters.length === 2) {
      const [a, b] = clusters.map((c) => Math.min(...c)).sort((x, y) => x - y);
      return { frequency: "semimonthly", anchorDate: last, semimonthlyDays: [a, b] };
    }
    return { frequency: "biweekly", anchorDate: last, semimonthlyDays: [1, 15] };
  }
  return null;
}
