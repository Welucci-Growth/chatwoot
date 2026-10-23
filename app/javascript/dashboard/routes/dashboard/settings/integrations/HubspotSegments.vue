<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import HubspotAPI from 'dashboard/api/integrations/hubspot';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const segments = ref([]);
const selectedIds = ref(new Set());
const search = ref('');
const isLoading = ref(true);
const isSaving = ref(false);
const hasError = ref(false);

const visibleSegments = computed(() => {
  const term = search.value.trim().toLowerCase();
  return term
    ? segments.value.filter(segment =>
        segment.name.toLowerCase().includes(term)
      )
    : segments.value;
});

const toggle = id => {
  const next = new Set(selectedIds.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  selectedIds.value = next;
};

const save = async () => {
  isSaving.value = true;
  try {
    await HubspotAPI.updateSegments([...selectedIds.value]);
    useAlert(t('HUBSPOT_SEGMENTS.SAVE_SUCCESS'));
  } catch {
    useAlert(t('HUBSPOT_SEGMENTS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(async () => {
  try {
    const { data } = await HubspotAPI.getSegments();
    segments.value = data.segments;
    selectedIds.value = new Set(
      data.segments.filter(segment => segment.selected).map(s => s.id)
    );
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <div
    class="flex flex-col gap-4 p-6 mt-6 border rounded-xl border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col gap-1">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('HUBSPOT_SEGMENTS.TITLE') }}
      </h3>
      <p class="text-sm text-n-slate-11">
        {{ t('HUBSPOT_SEGMENTS.DESCRIPTION') }}
      </p>
    </div>

    <div v-if="isLoading" class="flex justify-center py-6">
      <Spinner />
    </div>
    <p v-else-if="hasError" class="text-sm text-n-ruby-11">
      {{ t('HUBSPOT_SEGMENTS.LOAD_ERROR') }}
    </p>
    <template v-else>
      <Input
        v-model="search"
        :placeholder="t('HUBSPOT_SEGMENTS.SEARCH_PLACEHOLDER')"
      />
      <p v-if="!visibleSegments.length" class="text-sm text-n-slate-11">
        {{ t('HUBSPOT_SEGMENTS.EMPTY') }}
      </p>
      <ul
        v-else
        class="flex flex-col overflow-y-auto divide-y max-h-96 divide-n-weak"
      >
        <li
          v-for="segment in visibleSegments"
          :key="segment.id"
          class="flex items-center gap-3 py-2 cursor-pointer"
          @click="toggle(segment.id)"
        >
          <Checkbox
            :model-value="selectedIds.has(segment.id)"
            @click.stop
            @change="toggle(segment.id)"
          />
          <span class="flex-1 text-sm text-n-slate-12">{{ segment.name }}</span>
          <span class="text-xs text-n-slate-11">
            {{
              t('HUBSPOT_SEGMENTS.SIZE', {
                count: segment.size,
              })
            }}
          </span>
        </li>
      </ul>
      <div class="flex items-center justify-between gap-3">
        <span class="text-xs text-n-slate-11">
          {{
            t('HUBSPOT_SEGMENTS.SELECTED', {
              count: selectedIds.size,
            })
          }}
        </span>
        <Button
          :label="t('HUBSPOT_SEGMENTS.SAVE')"
          :is-loading="isSaving"
          @click="save"
        />
      </div>
    </template>
  </div>
</template>
