<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { waitingInfo } from '../helpers/waiting';

const props = defineProps({
  task: { type: Object, required: true },
  now: { type: Number, default: () => Date.now() },
});

defineEmits(['click', 'delete']);

const { t } = useI18n();

const dueLabel = computed(() => {
  if (!props.task.dueOn) return '';
  return new Date(props.task.dueOn * 1000).toLocaleDateString();
});

const waiting = computed(() => waitingInfo(props.task.waitingSince, props.now));

const waitingTone = computed(() => {
  if (!waiting.value) return { border: 'border-n-weak', chip: '' };
  return waiting.value.isLate
    ? {
        border: 'border-n-ruby-8 ring-1 ring-n-ruby-8',
        chip: 'bg-n-ruby-3 text-n-ruby-11',
      }
    : { border: 'border-n-amber-8', chip: 'bg-n-amber-3 text-n-amber-11' };
});

// The shortcut out to the CRM that mirrored this card. The chip carries the CRM's own
// name, so it is a brand rather than a translatable string.
const crm = computed(() => {
  const attrs = props.task.customAttributes || {};
  if (attrs.pipedrive?.url)
    return { name: 'Pipedrive', url: attrs.pipedrive.url };
  if (attrs.hubspot?.url) return { name: 'HubSpot', url: attrs.hubspot.url };
  return null;
});
</script>

<template>
  <div
    class="relative flex flex-col gap-2 p-3 transition-all border shadow-sm cursor-pointer group bg-n-solid-2 rounded-xl hover:shadow-md hover:border-n-strong"
    :class="waitingTone.border"
    @click="$emit('click')"
  >
    <div
      v-if="waiting"
      class="inline-flex items-center self-start gap-1 px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
      :class="waitingTone.chip"
      :title="t('TASKS.WAITING_REPLY')"
    >
      <span class="i-lucide-reply size-3" />
      {{ waiting.label }}
    </div>
    <div class="flex items-start justify-between gap-2">
      <p class="text-sm font-medium leading-snug text-n-slate-12 line-clamp-3">
        {{ task.title }}
      </p>
      <button
        class="flex items-center justify-center transition-opacity rounded-md opacity-0 shrink-0 size-6 group-hover:opacity-100 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-9"
        @click.stop="$emit('delete')"
      >
        <span class="i-lucide-trash-2 size-3.5" />
      </button>
    </div>

    <p v-if="task.description" class="text-xs text-n-slate-11 line-clamp-2">
      {{ task.description }}
    </p>

    <a
      v-if="crm"
      :href="crm.url"
      target="_blank"
      rel="noopener noreferrer"
      class="inline-flex items-center self-start gap-1 px-1.5 py-0.5 rounded-md text-[11px] font-medium bg-n-alpha-2 text-n-slate-11 hover:text-n-brand"
      @click.stop
    >
      <span class="i-lucide-external-link size-3" />
      {{ crm.name }}
    </a>

    <div v-if="task.labels?.length" class="flex flex-wrap items-center gap-1">
      <span
        v-for="label in task.labels"
        :key="label"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[11px] font-medium bg-n-alpha-2 text-n-slate-11"
      >
        <span class="rounded-full size-1.5 bg-n-brand" />
        {{ label }}
      </span>
    </div>

    <div class="flex items-center justify-between gap-2 mt-0.5">
      <span
        v-if="task.overdue"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[11px] font-medium bg-n-ruby-3 text-n-ruby-11"
      >
        <span class="i-lucide-clock size-3" />
        {{ t('TASKS.OVERDUE') }}
      </span>
      <span v-else-if="dueLabel" class="text-[11px] text-n-slate-10">
        {{ dueLabel }}
      </span>
      <span v-else />

      <div class="flex items-center gap-2 min-w-0">
        <span v-if="task.contact" class="text-xs truncate text-n-slate-11">
          {{ task.contact.name }}
        </span>
        <Avatar
          v-if="task.assignee"
          :name="task.assignee.name"
          :src="task.assignee.thumbnail"
          :size="20"
          rounded-full
        />
      </div>
    </div>
  </div>
</template>
