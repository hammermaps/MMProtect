import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

const LS_URL = 'mm_server_url'
const LS_KEY = 'mm_api_key'

export const useAuthStore = defineStore('auth', () => {
  const serverUrl = ref(localStorage.getItem(LS_URL) ?? '')
  const apiKey    = ref(localStorage.getItem(LS_KEY) ?? '')

  const isLoggedIn = computed(() => !!serverUrl.value && !!apiKey.value)

  function login(url: string, key: string) {
    serverUrl.value = url.replace(/\/$/, '')
    apiKey.value    = key
    localStorage.setItem(LS_URL, serverUrl.value)
    localStorage.setItem(LS_KEY, key)
  }

  function logout() {
    serverUrl.value = ''
    apiKey.value    = ''
    localStorage.removeItem(LS_URL)
    localStorage.removeItem(LS_KEY)
  }

  return { serverUrl, apiKey, isLoggedIn, login, logout }
})
