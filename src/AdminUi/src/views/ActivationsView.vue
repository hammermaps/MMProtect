<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { fetchActivations, revokeActivation, deleteActivation, type ActivationDto } from '../api'
import ConfirmDialog from '../components/ConfirmDialog.vue'

const items    = ref<ActivationDto[]>([])
const error    = ref('')
const loading  = ref(true)
const licFilter = ref('')

type Action = { type: 'revoke' | 'delete'; item: ActivationDto }
const pending = ref<Action | null>(null)
const actLoading = ref(false)
const actError   = ref('')

async function load() {
  loading.value = true; error.value = ''
  try   { items.value = await fetchActivations(licFilter.value || undefined) }
  catch (e: unknown) { error.value = e instanceof Error ? e.message : 'Failed.' }
  finally { loading.value = false }
}
onMounted(load)

async function doAction() {
  if (!pending.value) return
  actLoading.value = true; actError.value = ''
  try {
    if (pending.value.type === 'revoke')
      await revokeActivation(pending.value.item.activationId)
    else
      await deleteActivation(pending.value.item.activationId)
    pending.value = null
    await load()
  } catch (e: unknown) {
    actError.value = e instanceof Error ? e.message : 'Failed.'
  } finally {
    actLoading.value = false
  }
}

function truncate(s: string, n = 20) { return s.length > n ? s.slice(0, n) + '…' : s }
function fmtDate(d: string) { return new Date(d).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' }) }
function statusClass(s: string) {
  return s === 'active' ? 'badge badge-green' : 'badge badge-red'
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <div class="page-title">Activations</div>
        <div class="page-subtitle">View and manage machine activations</div>
      </div>
    </div>

    <div v-if="error" class="alert alert-error" style="margin-bottom:16px">{{ error }}</div>

    <div class="panel">
      <div class="panel-header">
        <div class="panel-title">Activations</div>
        <div class="panel-actions">
          <div class="filter-bar">
            <input v-model="licFilter" type="text" placeholder="Filter by License ID…" @keyup.enter="load" />
          </div>
          <button class="btn btn-outline btn-sm" @click="load" :disabled="loading">Search</button>
        </div>
      </div>

      <div v-if="loading" class="loading"><div class="spinner"></div> Loading…</div>
      <template v-else>
        <div v-if="items.length === 0" class="empty">No activations found.</div>
        <table v-else>
          <thead>
            <tr>
              <th>Machine Fingerprint</th>
              <th>License ID</th>
              <th>Status</th>
              <th>First Seen</th>
              <th>Last Seen</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="act in items" :key="act.activationId">
              <td class="td-mono" :title="act.machineFingerprint">{{ truncate(act.machineFingerprint, 24) }}</td>
              <td class="td-mono td-truncate" :title="act.licenseId">{{ act.licenseId }}</td>
              <td><span :class="statusClass(act.status)">{{ act.status }}</span></td>
              <td>{{ fmtDate(act.firstSeenAt) }}</td>
              <td>{{ fmtDate(act.lastSeenAt) }}</td>
              <td style="display:flex;gap:6px;align-items:center">
                <button
                  v-if="act.status !== 'revoked'"
                  class="btn btn-outline btn-sm"
                  @click="pending = { type: 'revoke', item: act }; actError = ''"
                >Revoke</button>
                <button
                  class="btn btn-danger btn-sm"
                  @click="pending = { type: 'delete', item: act }; actError = ''"
                >Delete</button>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <ConfirmDialog
      v-if="pending"
      :title="pending.type === 'revoke' ? 'Revoke Activation' : 'Delete Activation'"
      :message="pending.type === 'revoke'
        ? `Block this machine from obtaining new leases?`
        : `Permanently delete this activation? The machine can re-activate if the license allows.`"
      :confirm-label="pending.type === 'revoke' ? 'Revoke' : 'Delete'"
      :danger="true"
      :loading="actLoading"
      @confirm="doAction"
      @cancel="pending = null"
    />

    <div v-if="actError" class="alert alert-error" style="margin-top:12px">{{ actError }}</div>
  </div>
</template>
