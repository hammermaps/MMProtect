<script setup lang="ts">
import { useRoute } from 'vue-router'
import { useAuthStore } from './stores/auth'
import NavBar from './components/NavBar.vue'

const route = useRoute()
const auth  = useAuthStore()
</script>

<template>
  <div v-if="!auth.isLoggedIn || route.path === '/login'">
    <RouterView />
  </div>
  <div v-else class="layout">
    <NavBar />
    <main class="main">
      <div class="page">
        <RouterView />
      </div>
    </main>
  </div>
</template>
