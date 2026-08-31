<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import LuciAPI from 'dashboard/api/luci';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const settings = ref(null);
const models = ref([]);
const inboxes = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);

const COSTS = {
  'claude-haiku-4-5': 'LUCI.MODEL_COST.HAIKU',
  'claude-sonnet-5': 'LUCI.MODEL_COST.SONNET',
  'claude-opus-5': 'LUCI.MODEL_COST.OPUS',
};

const activeOn = computed(() =>
  inboxes.value.length ? inboxes.value.join(', ') : t('LUCI.NO_INBOX')
);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await LuciAPI.getSettings();
    settings.value = data.settings;
    models.value = data.models || [];
    inboxes.value = data.inboxes || [];
  } finally {
    isLoading.value = false;
  }
};

const save = async () => {
  isSaving.value = true;
  try {
    await LuciAPI.updateSettings({
      system_prompt: settings.value.system_prompt,
      knowledge: settings.value.knowledge,
      model: settings.value.model,
      required_label: settings.value.required_label,
      enabled: settings.value.enabled,
    });
    useAlert(t('LUCI.SAVED'));
  } catch (error) {
    useAlert(t('LUCI.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full p-6 overflow-auto">
    <div class="max-w-3xl">
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ $t('LUCI.TITLE') }}
      </h1>
      <p class="mt-1 mb-6 text-sm text-n-slate-11">{{ $t('LUCI.SUBTITLE') }}</p>

      <p v-if="isLoading" class="text-sm text-n-slate-11">
        {{ $t('LUCI.LOADING') }}
      </p>

      <div v-else-if="settings" class="flex flex-col gap-6">
        <div
          class="flex flex-col gap-2 p-4 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <label class="flex items-center gap-2 mb-0">
            <input v-model="settings.enabled" type="checkbox" class="mb-0" />
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('LUCI.ENABLED') }}
            </span>
          </label>
          <p class="text-sm text-n-slate-11">
            {{ $t('LUCI.ACTIVE_ON', { inboxes: activeOn }) }}
          </p>
          <p class="text-sm text-n-slate-11">
            {{ $t('LUCI.LABEL_RULE', { label: settings.required_label }) }}
          </p>
        </div>

        <label>
          {{ $t('LUCI.MODEL') }}
          <select v-model="settings.model">
            <option v-for="m in models" :key="m" :value="m">{{ m }}</option>
          </select>
          <span class="text-sm text-n-slate-11">
            {{ $t(COSTS[settings.model] || 'LUCI.MODEL_COST.HAIKU') }}
          </span>
        </label>

        <label>
          {{ $t('LUCI.PROMPT') }}
          <textarea
            v-model="settings.system_prompt"
            rows="14"
            :placeholder="$t('LUCI.PROMPT_PLACEHOLDER')"
          />
          <span class="text-sm text-n-slate-11">{{
            $t('LUCI.PROMPT_HINT')
          }}</span>
        </label>

        <label>
          {{ $t('LUCI.KNOWLEDGE') }}
          <textarea
            v-model="settings.knowledge"
            rows="18"
            :placeholder="$t('LUCI.KNOWLEDGE_PLACEHOLDER')"
          />
          <span class="text-sm text-n-slate-11">
            {{ $t('LUCI.KNOWLEDGE_HINT') }}
          </span>
        </label>

        <label>
          {{ $t('LUCI.LABEL') }}
          <input v-model="settings.required_label" type="text" class="w-56" />
          <span class="text-sm text-n-slate-11">{{
            $t('LUCI.LABEL_HINT')
          }}</span>
        </label>

        <NextButton
          class="w-fit"
          :is-loading="isSaving"
          :label="$t('LUCI.SAVE')"
          @click="save"
        />
      </div>
    </div>
  </div>
</template>
