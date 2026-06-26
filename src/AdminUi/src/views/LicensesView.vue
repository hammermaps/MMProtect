<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { fetchLicenses, revokeLicense, type LicenseDto } from '../api'
import ConfirmDialog from '../components/ConfirmDialog.vue'

const items    = ref<LicenseDto[]>([])
const error    = ref('')
const loading  = ref(true)
const filter   = ref('')

const revoking     = ref<LicenseDto | null>(null)
const revokeReason = ref('')
const revokeLoading = ref(false)
const revokeError   = ref('')

async function load() {
  loading.value = true; error.value = ''
  try   { items.value = await fetchLicenses(filter.value || undefined) }
  catch (e: unknown) { error.value = e instanceof Error ? e.message : 'Failed.' }
  finally { loading.value = false }
}

onMounted(load)

async function doRevoke() {
  if (!revoking.value) return
  revokeLoading.value = true; revokeError.value = ''
  try {
    await revokeLicense(revoking.value.licenseId, revokeReason.value || undefined)
    revoking.value = null
    revokeReason.value = ''
    await load()
  } catch (e: unknown) {
    revokeError.value = e instanceof Error ? e.message : 'Failed.'
  } finally {
    revokeLoading.value = false
  }
}

function fmtDate(d: string | null) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
}
function statusClass(s: string) {
  if (s === 'active')   return 'badge badge-green'
  if (s === 'revoked')  return 'badge badge-red'
  if (s === 'expired')  return 'badge badge-gray'
  return 'badge badge-yellow'
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <div class="page-title">Licenses</div>
        <div class="page-subtitle">Manage and revoke customer licenses</div>
      </div>
    </div>

    <div v-if="error" class="alert alert-error" style="margin-bottom:16px">{{ error }}</div>

    <div class="panel">
      <div class="panel-header">
        <div class="panel-title">All Licenses</div>
        <div class="panel-actions">
          <div class="filter-bar">
            <select v-model="filter" @change="load">
              <option value="">All statuses</option>
              <option value="active">Active</option>
              <option value="revoked">Revoked</option>
              <option value="expired">Expired</option>
              <option value="suspended">Suspended</option>
            </select>
          </div>
          <button class="btn btn-outline btn-sm" @click="load" :disabled="loading">Refresh</button>
        </div>
      </div>

      <div v-if="loading" class="loading"><div class="spinner"></div> Loading…</div>
      <template v-else>
        <div v-if="items.length === 0" class="empty">No licenses found.</div>
        <table v-else>
          <thead>
            <tr>
              <th>License Key</th>
              <th>Customer</th>
              <th>Project</th>
              <th>Status</th>
              <th>Valid Until</th>
              <th>Max Act.</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="lic in items" :key="lic.licenseId">
              <td class="td-mono td-truncate" :title="lic.licenseKey">{{ lic.licenseKey }}</td>
              <td class="td-mono td-truncate" :title="lic.customerId">{{ lic.customerId }}</td>
              <td class="td-mono td-truncate" :title="lic.projectId">{{ lic.projectId }}</td>
              <td><span :class="statusClass(lic.status)">{{ lic.status }}</span></td>
              <td>{{ fmtDate(lic.validUntil) }}</td>
              <td>{{ lic.maxActivations }}</td>
              <td>
                <button
                  v-if="lic.status !== 'revoked'"
                  class="btn btn-danger btn-sm"
                  @click="revoking = lic; revokeReason = ''"
                >Revoke</button>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <!-- Revoke dialog -->
    <div v-if="revoking" class="modal-overlay" @click.self="revoking = null">
      <div class="modal">
        <div class="modal-title">Revoke License</div>
        <div class="modal-body">
          Revoke <strong>{{ revoking.licenseKey }}</strong>? All active leases will be blocked immediately.
        </div>
        <div v-if="revokeError" class="alert alert-error">{{ revokeError }}</div>
        <div class="form-group">
          <label>Reason (optional)</label>
          <input v-model="revokeReason" type="text" placeholder="e.g. non-payment" />
        </div>
        <div class="modal-actions">
          <button class="btn btn-outline" @click="revoking = null" :disabled="revokeLoading">Cancel</button>
          <button class="btn btn-danger" @click="doRevoke" :disabled="revokeLoading">
            <span v-if="revokeLoading" class="spinner" style="width:14px;height:14px;margin-right:6px"></span>
            Revoke
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
