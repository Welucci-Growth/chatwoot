<script setup>
import { computed } from 'vue';

// Typebot runs on its own origin, so it is embedded rather than reimplemented. Traefik relaxes
// its frame-ancestors header for this dashboard only; everywhere else it stays unframeable.
const typebotURL = computed(() => window.chatwootConfig?.typebotURL || '');
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <iframe
      v-if="typebotURL"
      :src="typebotURL"
      :title="$t('BOTS.TITLE')"
      class="flex-grow w-full border-0"
      allow="clipboard-write; clipboard-read"
    />
    <div v-else class="flex items-center justify-center flex-grow p-8">
      <div class="max-w-md text-center">
        <h2 class="mb-2 text-lg font-medium text-n-slate-12">
          {{ $t('BOTS.NOT_CONFIGURED.TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ $t('BOTS.NOT_CONFIGURED.BODY') }}
        </p>
      </div>
    </div>
  </div>
</template>
