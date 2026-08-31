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
const stats = ref({ conversations: 0, replies: 0, since_days: 30 });
const isLoading = ref(false);
const isSaving = ref(false);

const MODEL_COST = {
  'claude-haiku-4-5': 'LUCI.MODEL_COST.HAIKU',
  'claude-sonnet-5': 'LUCI.MODEL_COST.SONNET',
  'claude-opus-5': 'LUCI.MODEL_COST.OPUS',
};

const SKILLS = [
  { icon: 'i-lucide-user-round-pen', key: 'RECORD' },
  { icon: 'i-lucide-tags', key: 'CLASSIFY' },
  { icon: 'i-lucide-user-round-check', key: 'HANDOFF' },
];

const isLive = computed(() => settings.value?.enabled && inboxes.value.length);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await LuciAPI.getSettings();
    settings.value = data.settings;
    models.value = data.models || [];
    inboxes.value = data.inboxes || [];
    stats.value = data.stats || stats.value;
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
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div class="w-full max-w-4xl px-8 py-8 mx-auto">
      <header class="flex flex-wrap items-start justify-between gap-4 mb-8">
        <div class="flex items-start gap-3">
          <span
            class="grid text-white rounded-xl size-11 place-items-center bg-n-brand shrink-0"
          >
            <span class="size-5 i-lucide-sparkles" />
          </span>
          <div>
            <h1 class="text-xl font-semibold text-n-slate-12">
              {{ $t('LUCI.TITLE') }}
            </h1>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ $t('LUCI.SUBTITLE') }}
            </p>
          </div>
        </div>
        <NextButton
          :is-loading="isSaving"
          :label="$t('LUCI.SAVE')"
          :disabled="!settings"
          @click="save"
        />
      </header>

      <p v-if="isLoading" class="text-sm text-n-slate-11">
        {{ $t('LUCI.LOADING') }}
      </p>

      <div v-else-if="settings" class="flex flex-col gap-6">
        <section
          class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
          :class="isLive ? 'ring-1 ring-n-teal-7' : ''"
        >
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div class="flex items-center gap-3">
              <span
                class="size-2.5 rounded-full shrink-0"
                :class="isLive ? 'bg-n-teal-9' : 'bg-n-slate-8'"
              />
              <div>
                <p class="text-sm font-medium text-n-slate-12">
                  {{ isLive ? $t('LUCI.STATUS.LIVE') : $t('LUCI.STATUS.IDLE') }}
                </p>
                <p class="mt-0.5 text-sm text-n-slate-11">
                  {{
                    inboxes.length
                      ? $t('LUCI.ACTIVE_ON', { inboxes: inboxes.join(', ') })
                      : $t('LUCI.NO_INBOX')
                  }}
                </p>
              </div>
            </div>
            <label
              class="flex items-center gap-2 mb-0 text-sm font-medium cursor-pointer text-n-slate-12"
            >
              <input v-model="settings.enabled" type="checkbox" class="mb-0" />
              {{ $t('LUCI.ENABLED') }}
            </label>
          </div>

          <div
            class="grid grid-cols-2 gap-4 pt-4 mt-4 border-t sm:grid-cols-3 border-n-weak"
          >
            <div>
              <p class="text-xl font-semibold tabular-nums text-n-slate-12">
                {{ stats.conversations }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ $t('LUCI.STATS.CONVERSATIONS', { days: stats.since_days }) }}
              </p>
            </div>
            <div>
              <p class="text-xl font-semibold tabular-nums text-n-slate-12">
                {{ stats.replies }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ $t('LUCI.STATS.REPLIES', { days: stats.since_days }) }}
              </p>
            </div>
            <div>
              <p class="text-xl font-semibold text-n-slate-12">
                {{ settings.required_label }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ $t('LUCI.STATS.LABEL') }}
              </p>
            </div>
          </div>
        </section>

        <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
          <h2 class="mb-1 text-sm font-medium text-n-slate-12">
            {{ $t('LUCI.SKILLS.TITLE') }}
          </h2>
          <p class="mb-4 text-sm text-n-slate-11">
            {{ $t('LUCI.SKILLS.SUBTITLE') }}
          </p>
          <div class="grid gap-3 sm:grid-cols-3">
            <div
              v-for="skill in SKILLS"
              :key="skill.key"
              class="flex flex-col gap-1.5 p-3 rounded-lg bg-n-alpha-1"
            >
              <span :class="skill.icon" class="size-4 text-n-brand" />
              <p class="text-sm font-medium text-n-slate-12">
                {{ $t(`LUCI.SKILLS.${skill.key}.TITLE`) }}
              </p>
              <p class="text-xs leading-relaxed text-n-slate-11">
                {{ $t(`LUCI.SKILLS.${skill.key}.BODY`) }}
              </p>
            </div>
          </div>
        </section>

        <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
          <h2 class="mb-4 text-sm font-medium text-n-slate-12">
            {{ $t('LUCI.PROMPT') }}
          </h2>
          <textarea
            v-model="settings.system_prompt"
            class="w-full mb-2 font-mono text-sm !h-72 leading-relaxed"
            :placeholder="$t('LUCI.PROMPT_PLACEHOLDER')"
          />
          <p class="text-sm text-n-slate-11">{{ $t('LUCI.PROMPT_HINT') }}</p>
        </section>

        <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
          <h2 class="mb-4 text-sm font-medium text-n-slate-12">
            {{ $t('LUCI.KNOWLEDGE') }}
          </h2>
          <textarea
            v-model="settings.knowledge"
            class="w-full mb-2 font-mono text-sm !h-96 leading-relaxed"
            :placeholder="$t('LUCI.KNOWLEDGE_PLACEHOLDER')"
          />
          <p class="text-sm text-n-slate-11">{{ $t('LUCI.KNOWLEDGE_HINT') }}</p>
        </section>

        <section
          class="grid gap-6 p-5 border sm:grid-cols-2 rounded-xl border-n-weak bg-n-solid-1"
        >
          <div>
            <h2 class="mb-3 text-sm font-medium text-n-slate-12">
              {{ $t('LUCI.MODEL') }}
            </h2>
            <select v-model="settings.model" class="w-full mb-2">
              <option v-for="m in models" :key="m" :value="m">{{ m }}</option>
            </select>
            <p class="text-sm text-n-slate-11">
              {{ $t(MODEL_COST[settings.model] || 'LUCI.MODEL_COST.HAIKU') }}
            </p>
          </div>
          <div>
            <h2 class="mb-3 text-sm font-medium text-n-slate-12">
              {{ $t('LUCI.LABEL') }}
            </h2>
            <input
              v-model="settings.required_label"
              type="text"
              class="w-full mb-2"
            />
            <p class="text-sm text-n-slate-11">{{ $t('LUCI.LABEL_HINT') }}</p>
          </div>
        </section>

        <div class="flex justify-end pb-4">
          <NextButton
            :is-loading="isSaving"
            :label="$t('LUCI.SAVE')"
            @click="save"
          />
        </div>
      </div>
    </div>
  </div>
</template>
