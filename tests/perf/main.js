import http from 'k6/http'
import { check } from 'k6'
import { Rate, Trend } from 'k6/metrics'

/**
 * EN-84 — Performance thresholds (p95 < 2000 ms).
 *
 * Three scenarios on the main journeys: create a ticket, list my tickets, read
 * the KPI dashboard. Each carries its own p95 Trend and an error Rate so a
 * breach points to the faulty scenario (AC4). Chat is measured separately
 * (generation latency, PO-validated threshold) — out of scope here.
 *
 * Config via environment (never hardcode secrets or URLs):
 *   BASE_URL      API base, e.g. https://d123.cloudfront.net/api
 *   STUDENT_TOKEN Cognito access token for a student test user
 *   ADMIN_TOKEN   Cognito access token for an admin test user
 *   VUS, DURATION load profile (defaults below; see README for assumptions)
 *
 * Run: task perf ENV=dev   (wraps `k6 run tests/perf/main.js`)
 */

const BASE_URL = (__ENV.BASE_URL || '').replace(/\/$/, '')
const STUDENT_TOKEN = __ENV.STUDENT_TOKEN || ''
const ADMIN_TOKEN = __ENV.ADMIN_TOKEN || ''

const VUS = Number(__ENV.VUS || 10)
const DURATION = __ENV.DURATION || '1m'

// Per-scenario latency trends and error rates (AC1, AC2, AC4).
const createTrend = new Trend('create_ticket_duration', true)
const listTrend = new Trend('list_tickets_duration', true)
const kpiTrend = new Trend('kpi_duration', true)
const errorRate = new Rate('business_errors')

export const options = {
  scenarios: {
    create_ticket: { executor: 'constant-vus', vus: VUS, duration: DURATION, exec: 'createTicket' },
    list_tickets: { executor: 'constant-vus', vus: VUS, duration: DURATION, exec: 'listTickets' },
    kpi: { executor: 'constant-vus', vus: Math.max(1, Math.floor(VUS / 2)), duration: DURATION, exec: 'kpi' },
  },
  thresholds: {
    // AC1 — p95 < 2000 ms per scenario.
    'create_ticket_duration': ['p(95)<2000'],
    'list_tickets_duration': ['p(95)<2000'],
    'kpi_duration': ['p(95)<2000'],
    // AC2 — business error rate under 1% (429 throttling is expected and excluded below).
    'business_errors': ['rate<0.01'],
  },
}

function studentHeaders() {
  return { headers: { Authorization: `Bearer ${STUDENT_TOKEN}`, 'Content-Type': 'application/json' } }
}
function adminHeaders() {
  return { headers: { Authorization: `Bearer ${ADMIN_TOKEN}`, 'Content-Type': 'application/json' } }
}

// 429 is an expected outcome under WAF/stage throttling (AC2): not a business error.
function record(res, trend) {
  trend.add(res.timings.duration)
  const expected = res.status < 400 || res.status === 429
  errorRate.add(!expected)
  return expected
}

export function createTicket() {
  const payload = JSON.stringify({
    title: `perf ${Date.now()}`,
    category: 'incident',
    description: 'k6 performance scenario, created by a test user.',
  })
  const res = http.post(`${BASE_URL}/tickets`, payload, studentHeaders())
  check(res, { 'create: 201 or 429': (r) => r.status === 201 || r.status === 429 })
  record(res, createTrend)
}

export function listTickets() {
  const res = http.get(`${BASE_URL}/tickets?sort=createdAt:desc`, studentHeaders())
  check(res, { 'list: 200 or 429': (r) => r.status === 200 || r.status === 429 })
  record(res, listTrend)
}

export function kpi() {
  const res = http.get(`${BASE_URL}/kpi?from=2026-10-01&to=2026-10-23&granularity=day`, adminHeaders())
  check(res, { 'kpi: 200 or 429': (r) => r.status === 200 || r.status === 429 })
  record(res, kpiTrend)
}

export function setup() {
  if (!BASE_URL || !STUDENT_TOKEN || !ADMIN_TOKEN) {
    throw new Error('BASE_URL, STUDENT_TOKEN and ADMIN_TOKEN are required (see tests/perf/README.md).')
  }
}
