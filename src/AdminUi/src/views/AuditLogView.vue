<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { fetchAuditLog, type AuditEventDto } from '../api'

const items   = ref<AuditEventDto[]>([])
const error   = ref('')
const loading = ref(true)

const filterType = ref('')
const filterUid  = ref('')
const limit      = ref(100)

async function load() {
  loading.value = true; error.value = ''
  const params: Record<string, string> = { limit: String(limit.value) }
  if (filterType.value) params.entityType = filterType.value
  if (filterUid.value)  params.entityUid  = filterUid.value
  try   { items.value = await fetchAuditLog(params) }
  catch (e: unknown) { error.value = e instanceof Error ? e.message : 'Failed.' }
  finally { loading.value = false }
}
onMounted(load)

function fmtDate(d: string) {
  return new Date(d).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'medium' })
}
function eventClass(t: string) {
  if (t.includes('granted'))  return 'badge badge-green'
  if (t.includes('denied') || t.includes('rejected')) return 'badge badge-red'
  if (t.includes('revoked')) return 'badge badge-red'
  if (t.includes('started') || t.includes('signed')) return 'badge badge-blue'
  return 'badge badge-gray'
}
function actorClass(a: string) {
  if (a === 'loader')  return 'badge badge-blue'
  if (a === 'encoder') return 'badge badge-yellow'
  if (a === 'admin')   return 'badge badge-gray'
  return 'badge badge-gray'
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <div class="page-title">Audit Log</div>
        <div class="page-subtitle">Security and operation events</div>
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
          <label style="display:block;margin-bottom:5px">Entity Type</label>
          <select v-model="filterType" style="width:160px">
            <option value="">All</option>
            <option value="license">license</option>
            <option value="build">build</option>
            <option value="activation">activation</option>
            <option value="api_client">api_client</option>
          </select>
        </div>
        <div>
          <label style="display:block;margin-bottom:5px">Entity UID</label>
          <input v-model="filterUid" type="text" placeholder="e.g. lic_abc123" style="width:220px" />
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
        <div class="panel-title">Events ({{ items.length }})</div>
        <div class="panel-actions">
          <button class="btn btn-outline btn-sm" @click="load" :disabled="loading">Refresh</button>
        </div>
      </div>
      <div v-if="loading" class="loading"><div class="spinner"></div> Loading…</div>
      <template v-else>
        <div v-if="items.length === 0" class="empty">No events found.</div>
        <table v-else style="font-size:12.5px">
          <thead>
            <tr>
              <th>Time</th>
              <th>Actor</th>
              <th>Event</th>
              <th>Entity</th>
              <th>UID</th>
              <th>IP</th>
              <th>Details</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="ev in items" :key="ev.eventId">
              <td style="white-space:nowrap">{{ fmtDate(ev.createdAt) }}</td>
              <td><span :class="actorClass(ev.actorType)">{{ ev.actorType }}</span></td>
              <td><span :class="eventClass(ev.eventType)">{{ ev.eventType }}</span></td>
              <td>{{ ev.entityType ?? '—' }}</td>
              <td class="td-mono td-truncate" style="max-width:140px" :title="ev.entityUid ?? ''">{{ ev.entityUid ?? '—' }}</td>
              <td class="td-mono">{{ ev.ipAddress ?? '—' }}</td>
              <td class="td-truncate" style="max-width:200px" :title="ev.details ?? ''">{{ ev.details ?? '—' }}</td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>
  </div>
</template>
