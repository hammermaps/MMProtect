<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { checkHealth } from '../api'

const router = useRouter()
const auth   = useAuthStore()

const serverUrl = ref(auth.serverUrl || 'http://localhost:8080')
const apiKey    = ref('')
const error     = ref('')
const loading   = ref(false)

async function submit() {
  error.value   = ''
  loading.value = true
  try {
    const res = await checkHealth(serverUrl.value, apiKey.value)
    if (res.status === 401) { error.value = 'Invalid API key.'; return }
    if (!res.ok)            { error.value = `Server error: HTTP ${res.status}`; return }
    auth.login(serverUrl.value, apiKey.value)
    router.push('/')
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : 'Connection failed.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-wrap">
    <div class="login-box">
      <div class="login-logo">MM<span style="color:#64748b">Protect</span></div>
      <div class="login-heading">Admin Login</div>
      <div class="login-sub">Enter your license server URL and admin API key.</div>

      <div v-if="error" class="alert alert-error">{{ error }}</div>

      <form @submit.prevent="submit">
        <div class="form-group">
          <label for="url">Server URL</label>
          <input id="url" v-model="serverUrl" type="text" placeholder="https://license.example.com" required />
        </div>
        <div class="form-group">
          <label for="key">Admin API Key</label>
          <input id="key" v-model="apiKey" type="password" placeholder="Bearer token" required />
          <div class="form-hint">Set via <code>Security:AdminApiKeys</code> in appsettings.json.</div>
        </div>
        <button type="submit" class="btn btn-primary" style="width:100%" :disabled="loading">
          <span v-if="loading" class="spinner" style="width:14px;height:14px;margin-right:6px"></span>
          Sign in
        </button>
      </form>
    </div>
  </div>
</template>
