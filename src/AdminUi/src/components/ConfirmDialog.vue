<script setup lang="ts">
defineProps<{
  title: string
  message: string
  confirmLabel?: string
  danger?: boolean
  loading?: boolean
}>()

const emit = defineEmits<{
  confirm: []
  cancel: []
}>()
</script>

<template>
  <div class="modal-overlay" @click.self="emit('cancel')">
    <div class="modal">
      <div class="modal-title">{{ title }}</div>
      <div class="modal-body">{{ message }}</div>
      <div class="modal-actions">
        <button class="btn btn-outline" @click="emit('cancel')" :disabled="loading">Cancel</button>
        <button
          class="btn"
          :class="danger ? 'btn-danger' : 'btn-primary'"
          @click="emit('confirm')"
          :disabled="loading"
        >
          <span v-if="loading" class="spinner" style="width:14px;height:14px;margin-right:6px"></span>
          {{ confirmLabel ?? 'Confirm' }}
        </button>
      </div>
    </div>
  </div>
</template>
