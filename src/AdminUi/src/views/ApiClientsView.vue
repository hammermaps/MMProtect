<script setup lang="ts">
import { ref, onMounted } from 'vue'
import {
  fetchApiClients, createApiClient, deleteApiClient,
  type ApiClientDto, type ApiClientCreateResponse,
} from '../api'
import ConfirmDialog from '../components/ConfirmDialog.vue'

const items   = ref<ApiClientDto[]>([])
const error   = ref('')
const loading = ref(true)

// Create form
const showCreate  = ref(false)
const newName     = ref('')
const newScope    = ref('encoder')
const createLoading = ref(false)
const createError   = ref('')
const newKey        = ref<ApiClientCreateResponse | null>(null)
const keyCopied     = ref(false)

// Delete
const deleting   = ref<ApiClientDto | null>(null)
const delLoading = ref(false)
const delError   = ref('')

async function load() {
  loading.value = true; error.value = ''
  try   { items.value = await fetchApiClients() }
  catch (e: unknown) { error.value = e instanceof Error ? e.message : 'Failed.' }
  finally { loading.value = false }
}
onMounted(load)

async function doCreate() {
  if (!newName.value.trim()) { createError.value = 'Name is required.'; return }
  createLoading.value = true; createError.value = ''
  try {
    newKey.value = await createApiClient(newName.value.trim(), newScope.value)
    newName.value = ''
    newScope.value = 'encoder'
    showCreate.value = false
    keyCopied.value = false
    await load()
  } catch (e: unknown) {
    createError.value = e instanceof Error ? e.message : 'Failed.'
  } finally {
    createLoading.value = false
  }
}

async function doDelete() {
  if (!deleting.value) return
  delLoading.value = true; delError.value = ''
  try {
    await deleteApiClient(deleting.value.clientUid)
    deleting.value = null
    await load()
  } catch (e: unknown) {
    delError.value = e instanceof Error ? e.message : 'Failed.'
  } finally {
    delLoading.value = false
  }
}

function copyKey() {
  if (newKey.value) {
    navigator.clipboard.writeText(newKey.value.apiKey)
    keyCopied.value = true
    setTimeout(() => { keyCopied.value = false }, 2000)
  }
}

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
}
</script>

<template>
  <div>
    <div class="page-header">
      <div>
        <div class="page-title">API Clients</div>
        <div class="page-subtitle">Manage programmatic access keys</div>
      </div>
      <button class="btn btn-primary" @click="showCreate = !showCreate">
        + New Client
      </button>
    </div>

    <!-- Create form -->
    <div v-if="showCreate" class="panel" style="margin-bottom:20px">
      <div class="panel-header">
        <div class="panel-title">New API Client</div>
      </div>
      <div style="padding:20px 24px">
        <div v-if="createError" class="alert alert-error">{{ createError }}</div>
        <div style="display:flex;gap:16px;align-items:flex-end;flex-wrap:wrap">
          <div class="form-group" style="flex:1;min-width:180px;margin-bottom:0">
            <label>Name</label>
            <input v-model="newName" type="text" placeholder="e.g. CI/CD Pipeline" />
          </div>
          <div class="form-group" style="margin-bottom:0">
            <label>Scope</label>
            <select v-model="newScope">
              <option value="encoder">encoder</option>
              <option value="admin">admin</option>
              <option value="all">all</option>
            </select>
          </div>
          <button class="btn btn-primary" @click="doCreate" :disabled="createLoading">
            <span v-if="createLoading" class="spinner" style="width:14px;height:14px;margin-right:6px"></span>
            Create
          </button>
          <button class="btn btn-outline" @click="showCreate = false">Cancel</button>
        </div>
      </div>
    </div>

    <!-- New key reveal -->
    <div v-if="newKey" class="panel" style="margin-bottom:20px">
      <div class="panel-header">
        <div class="panel-title" style="color:var(--success)">API Key Created</div>
      </div>
      <div style="padding:20px 24px">
        <div class="alert alert-info" style="margin-bottom:12px">
          Copy this key now — it will <strong>not</strong> be shown again.
        </div>
        <div class="key-box">{{ newKey.apiKey }}</div>
        <div style="display:flex;gap:10px;margin-top:12px">
          <button class="btn btn-primary" @click="copyKey">
            {{ keyCopied ? 'Copied!' : 'Copy to Clipboard' }}
          </button>
          <button class="btn btn-outline" @click="newKey = null">Dismiss</button>
        </div>
      </div>
    </div>

    <div v-if="error" class="alert alert-error" style="margin-bottom:16px">{{ error }}</div>

    <div class="panel">
      <div class="panel-header">
        <div class="panel-title">All Clients</div>
        <div class="panel-actions">
          <button class="btn btn-outline btn-sm" @click="load" :disabled="loading">Refresh</button>
        </div>
      </div>

      <div v-if="loading" class="loading"><div class="spinner"></div> Loading…</div>
      <template v-else>
        <div v-if="items.length === 0" class="empty">No API clients. Create one above.</div>
        <table v-else>
          <thead>
            <tr>
              <th>Name</th>
              <th>Scope</th>
              <th>Status</th>
              <th>Created</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in items" :key="c.clientUid">
              <td>{{ c.name }}</td>
              <td><span class="badge badge-blue">{{ c.scope }}</span></td>
              <td>
                <span :class="c.isActive ? 'badge badge-green' : 'badge badge-red'">
                  {{ c.isActive ? 'active' : 'revoked' }}
                </span>
              </td>
              <td>{{ fmtDate(c.createdAt) }}</td>
              <td>
                <button
                  v-if="c.isActive"
                  class="btn btn-danger btn-sm"
                  @click="deleting = c; delError = ''"
                >Revoke</button>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <ConfirmDialog
      v-if="deleting"
      title="Revoke API Client"
      :message="`Revoke access for '${deleting.name}'? This cannot be undone.`"
      confirm-label="Revoke"
      :danger="true"
      :loading="delLoading"
      @confirm="doDelete"
      @cancel="deleting = null"
    />
    <div v-if="delError" class="alert alert-error" style="margin-top:12px">{{ delError }}</div>
  </div>
</template>
