<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { fetchErrorReports, type ErrorReportDto } from '../api'

const items   = ref<ErrorReportDto[]>([])
const error   = ref('')
const loading = ref(true)

const filterLicenseId = ref('')
const filterBuildId   = ref('')
const limit           = ref(100)

async function load() {
  loading.value = true; error.value = ''
  const params: Record<string, string> = { limit: String(limit.value) }
  if (filterLicenseId.value) params.licenseId = filterLicenseId.value
  if (filterBuildId.value)   params.buildId   = filterBuildId.value
  try   { items.value = await fetchErrorReports(params) }
  catch (e: unknown) { error.value = e instanceof Error ? e.message : 'Failed.' }
  finally { loading.value = false }
}
onMounted(load)

function fmtDate(d: string) {
  return new Date(d).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'medium' })
}

function levelLabel(n: number): string {
  const map: Record<number, string> = {
    1: 'E_ERROR', 2: 'E_WARNING', 4: 'E_PARSE', 8: 'E_NOTICE',
    256: 'E_USER_ERROR', 512: 'E_USER_WARNING', 1024: 'E_USER_NOTICE',
    2048: 'E_STRICT', 8192: 'E_DEPRECATED', 16384: 'E_USER_DEPRECATED',
  }
  return map[n] ?? `E_${n}`
}

function levelClass(n: number): string {
  if (n === 1 || n === 4 || n === 256) return 'badge badge-red'
  if (n === 2 || n === 512)            return 'badge badge-yellow'
  if (n === 8 || n === 1024)           return 'badge badge-gray'
  return 'badge badge-gray'
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <div class="page-title">Error Reports</div>
        <div class="page-subtitle">PHP errors reported by mmloader from customer servers</div>
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
          <label style="display:block;margin-bottom:5px">License ID</label>
          <input v-model="filterLicenseId" type="text" placeholder="lic_…" style="width:220px" />
        </div>
        <div>
          <label style="display:block;margin-bottom:5px">Build ID</label>
          <input v-model="filterBuildId" type="text" placeholder="build_…" style="width:220px" />
        </div>
        <div>
          <label style="display:block;margin-bottom:5px">Limit</label>
          <select v-model="limit" style="width:100px">
            <option :value="50">50</option>
            <option :value="100">100</option>
            <option :value="500">500</option>
          </select>
        </div>
      </div>
    </div>

    <div v-if="error" class="alert alert-error" style="margin-bottom:16px">{{ error }}</div>

    <div class="panel">
      <div class="panel-header">
        <div class="panel-title">Reports ({{ items.length }})</div>
        <div class="panel-actions">
          <button class="btn btn-outline btn-sm" @click="load" :disabled="loading">Refresh</button>
        </div>
      </div>
      <div v-if="loading" class="loading"><div class="spinner"></div> Loading…</div>
      <template v-else>
        <div v-if="items.length === 0" class="empty">No error reports found.</div>
        <table v-else style="font-size:12.5px">
          <thead>
            <tr>
              <th>Time</th>
              <th>Level</th>
              <th>Message</th>
              <th>File</th>
              <th>Line</th>
              <th>PHP</th>
              <th>SAPI</th>
              <th>License ID</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="rep in items" :key="rep.id">
              <td style="white-space:nowrap">{{ fmtDate(rep.reportedAt) }}</td>
              <td><span :class="levelClass(rep.errorLevel)">{{ levelLabel(rep.errorLevel) }}</span></td>
              <td class="td-truncate" style="max-width:260px" :title="rep.errorMessage">{{ rep.errorMessage }}</td>
              <td class="td-mono td-truncate" style="max-width:160px" :title="rep.errorFile ?? ''">{{ rep.errorFile ?? '—' }}</td>
              <td class="td-mono">{{ rep.errorLine ?? '—' }}</td>
              <td class="td-mono">{{ rep.phpVersion ?? '—' }}</td>
              <td>{{ rep.sapi ?? '—' }}</td>
              <td class="td-mono td-truncate" style="max-width:120px" :title="rep.licenseId">{{ rep.licenseId }}</td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>
  </div>
</template>
