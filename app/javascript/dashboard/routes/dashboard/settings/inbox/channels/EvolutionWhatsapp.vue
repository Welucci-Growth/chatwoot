<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, url } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import router from '../../../../index';
import NextButton from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const inboxName = ref('');
const phoneNumber = ref('');
const baseUrl = ref('');
const instance = ref('');
const apiKey = ref('');
const createdInbox = ref(null);

const rules = {
  inboxName: { required },
  phoneNumber: { required, isPhoneE164OrEmpty },
  baseUrl: { required, url },
  instance: { required },
  apiKey: { required },
};

const v$ = useVuelidate(rules, {
  inboxName,
  phoneNumber,
  baseUrl,
  instance,
  apiKey,
});

const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

const webhookUrl = computed(() => {
  const token = createdInbox.value?.provider_config?.webhook_verify_token;
  return `${window.chatwootConfig.hostURL}/webhooks/evolution/${token}`;
});

const createChannel = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    createdInbox.value = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value.trim(),
      channel: {
        type: 'whatsapp',
        phone_number: phoneNumber.value,
        provider: 'evolution',
        provider_config: {
          base_url: baseUrl.value.trim().replace(/\/+$/, ''),
          instance: instance.value.trim(),
          api_key: apiKey.value.trim(),
        },
      },
    });
  } catch (error) {
    useAlert(
      error.message || t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.API.ERROR_MESSAGE')
    );
  }
};

const copyWebhookUrl = () => {
  copyTextToClipboard(webhookUrl.value);
  useAlert(t('CONTACT_PANEL.COPY_SUCCESSFUL'));
};

const goToAgents = () => {
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: createdInbox.value.id },
  });
};
</script>

<template>
  <div v-if="createdInbox" class="flex flex-col gap-4">
    <h6 class="text-base font-medium text-n-slate-12">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.WEBHOOK.TITLE') }}
    </h6>
    <p class="text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.WEBHOOK.BODY') }}
    </p>
    <div
      class="flex gap-2 items-center p-3 rounded-lg border border-n-weak bg-n-slate-2"
    >
      <code class="overflow-x-auto flex-grow text-xs text-n-slate-12">
        {{ webhookUrl }}
      </code>
      <NextButton
        sm
        faded
        slate
        icon="i-ri-file-copy-line"
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.WEBHOOK.COPY')"
        @click="copyWebhookUrl"
      />
    </div>
    <NextButton
      class="w-fit"
      :label="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
      @click="goToAgents"
    />
  </div>

  <form v-else class="flex flex-col gap-4 mx-0" @submit.prevent="createChannel">
    <div
      class="p-3 text-sm rounded-lg border border-n-amber-6 bg-n-amber-3 text-n-amber-11"
    >
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.READ_ONLY_NOTICE') }}
    </div>

    <label :class="{ error: v$.inboxName.$error }">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
      <input
        v-model="inboxName"
        type="text"
        :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
        @blur="v$.inboxName.$touch"
      />
      <span v-if="v$.inboxName.$error" class="message">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
      </span>
    </label>

    <label :class="{ error: v$.phoneNumber.$error }">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
      <input
        v-model="phoneNumber"
        type="text"
        :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
        @blur="v$.phoneNumber.$touch"
      />
      <span v-if="v$.phoneNumber.$error" class="message">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
      </span>
    </label>

    <label :class="{ error: v$.baseUrl.$error }">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.BASE_URL.LABEL') }}
      <input
        v-model="baseUrl"
        type="text"
        :placeholder="
          $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.BASE_URL.PLACEHOLDER')
        "
        @blur="v$.baseUrl.$touch"
      />
      <span v-if="v$.baseUrl.$error" class="message">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.BASE_URL.ERROR') }}
      </span>
    </label>

    <label :class="{ error: v$.instance.$error }">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE.LABEL') }}
      <input
        v-model="instance"
        type="text"
        :placeholder="
          $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE.PLACEHOLDER')
        "
        @blur="v$.instance.$touch"
      />
      <span v-if="v$.instance.$error" class="message">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE.ERROR') }}
      </span>
    </label>

    <label :class="{ error: v$.apiKey.$error }">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.API_KEY.LABEL') }}
      <input
        v-model="apiKey"
        type="password"
        :placeholder="
          $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.API_KEY.PLACEHOLDER')
        "
        @blur="v$.apiKey.$touch"
      />
      <span v-if="v$.apiKey.$error" class="message">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.API_KEY.ERROR') }}
      </span>
    </label>

    <NextButton
      class="w-fit"
      type="submit"
      :is-loading="uiFlags.isCreating"
      :label="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
    />
  </form>
</template>
