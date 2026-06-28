<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { fetchTelemetry, type TelemetryDto } from '../api'

const items   = ref<TelemetryDto[]>([])
const error   = ref('')
const loading = ref(true)

const filterSource    = ref('')
const filterLicenseId = ref('')
const filterProjectId = ref('')
const limit           = ref(200)

async function load() {
  loading.value = true; error.value = ''
  const params: Record<string, string> = { limit: String(limit.value) }
  if (filterSource.value)    params.source    = filterSource.value
  if (filterLicenseId.value) params.licenseId = filterLicenseId.value
  if (filterProjectId.value) params.projectId = filterProjectId.value
  try   { items.value = await fetchTelemetry(params) }
  catch (e: unknown) { error.value = e instanceof Error ? e.message : 'Failed.' }
  finally { loading.value = false }
}
onMounted(load)

function fmtDate(d: string) {
  return new Date(d).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'medium' })
}

function sourceClass(s: string) {
  if (s === 'encoder') return 'badge badge-yellow'
  if (s === 'loader')  return 'badge badge-blue'
  return 'badge badge-gray'
}

function eventClass(t: string) {
  if (t.includes('completed') || t.includes('acquired')) return 'badge badge-green'
  if (t.includes('failed'))                              return 'badge badge-red'
  if (t.includes('started') || t.includes('grace'))     return 'badge badge-blue'
  return 'badge badge-gray'
}

function parsePayload(raw: string | null): string {
  if (!raw) return '—'
  try {
    const obj = JSON.parse(raw)
    return Object.entries(obj).map(([k, v]) => `${k}: ${v}`).join(' · ')
  } catch { return raw }
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <div class="page-title">Telemetry</div>
        <div class="page-subtitle">Build and lease lifecycle events from Encoder and Loader</div>
      </div>
    </div>

    <div class="panel" style="margin-bottom:16px">
      <div class="panel-header">
        <div class="panel-title">Filters</div>
        <div class="panel-actions">
          <button class="btn btn-primary btn-sm" @click="load" :disabled="loading">Apply</button>
        </div>
      </div>
      <div style="padding:16px 20px;display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end">
        <div>
          <label style="display:block;margin-bottom:5px">Source</label>
          <select v-model="filterSource" style="width:140px">
            <option value="">All</option>
            <option value="encoder">encoder</option>
            <option value="loader">loader</option>
          </select>
        </div>
        <div>
          <label style="display:block;margin-bottom:5px">License ID</label>
          <input v-model="filterLicenseId" type="text" placeholder="lic_…" style="width:220px" />
        </div>
        <div>
          <label style="display:block;margin-bottom:5px">Project ID</label>
          <input v-model="filterProjectId" type="text" placeholder="proj_…" style="width:220px" />
        </div>
        <div>
          <label style="display:block;margin-bottom:5px">Limit</label>
          <select v-model="limit" style="width:100px">
            <option :value="100">100</option>
            <option :value="200">200</option>
            <option :value="500">500</option>
          </select>
        </div>
      </div>
    </div>

    <div v-if="error" class="alert alert-error" style="margin-bottom:16px">{{ error }}</div>

    <div class="panel">
      <div class="panel-header">
        <div class="panel-title">Events ({{ items.length }})</div>
        <div class="panel-actions">
          <button class="btn btn-outline btn-sm" @click="load" :disabled="loading">Refresh</button>
        </div>
      </div>
      <div v-if="loading" class="loading"><div class="spinner"></div> Loading…</div>
      <template v-else>
        <div v-if="items.length === 0" class="empty">No telemetry events found.</div>
        <table v-else style="font-size:12.5px">
          <thead>
            <tr>
              <th>Time</th>
              <th>Source</th>
              <th>Event</th>
              <th>License ID</th>
              <th>Build ID</th>
              <th>Project ID</th>
              <th>Data</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="ev in items" :key="ev.id">
              <td style="white-space:nowrap">{{ fmtDate(ev.occurredAt) }}</td>
              <td><span :class="sourceClass(ev.source)">{{ ev.source }}</span></td>
              <td><span :class="eventClass(ev.eventType)">{{ ev.eventType }}</span></td>
              <td class="td-mono td-truncate" style="max-width:130px" :title="ev.licenseId ?? ''">{{ ev.licenseId ?? '—' }}</td>
              <td class="td-mono td-truncate" style="max-width:130px" :title="ev.buildId ?? ''">{{ ev.buildId ?? '—' }}</td>
              <td class="td-mono td-truncate" style="max-width:110px" :title="ev.projectId ?? ''">{{ ev.projectId ?? '—' }}</td>
              <td class="td-truncate" style="max-width:220px" :title="parsePayload(ev.payloadJson)">{{ parsePayload(ev.payloadJson) }}</td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>
  </div>
</template>
