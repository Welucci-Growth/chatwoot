<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  task: { type: Object, default: null },
  stageName: { type: String, default: '' },
});

const { t } = useI18n();

const dialogRef = ref(null);

const open = () => dialogRef.value.open();
const close = () => dialogRef.value.close();
defineExpose({ open, close });

const crm = computed(() => props.task?.customAttributes?.pipedrive || {});
const amounts = computed(() => crm.value.amounts || {});
const fields = computed(() => crm.value.fields || []);

const formatMoney = value =>
  new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: amounts.value.currency || 'BRL',
    maximumFractionDigits: 0,
  }).format(value);

const formatDate = value => (value ? new Date(value).toLocaleDateString() : '');

// Os valores recorrentes só aparecem quando o CRM tem o número preenchido.
const money = computed(() =>
  [
    { key: 'value', label: t('TASKS.DETAIL.VALUE') },
    { key: 'mrr', label: t('TASKS.DETAIL.MRR') },
    { key: 'arr', label: t('TASKS.DETAIL.ARR') },
    { key: 'acv', label: t('TASKS.DETAIL.ACV') },
  ]
    .filter(item => Number(amounts.value[item.key]) > 0)
    .map(item => ({ ...item, amount: formatMoney(amounts.value[item.key]) }))
);

const statusTone = computed(
  () =>
    ({
      won: 'bg-n-teal-3 text-n-teal-11',
      lost: 'bg-n-ruby-3 text-n-ruby-11',
    })[crm.value.status] || 'bg-n-alpha-2 text-n-slate-11'
);

const statusLabel = computed(
  () =>
    ({
      won: t('TASKS.DETAIL.STATUS.WON'),
      lost: t('TASKS.DETAIL.STATUS.LOST'),
      open: t('TASKS.DETAIL.STATUS.OPEN'),
    })[crm.value.status] || ''
);

const summary = computed(() =>
  [
    { label: t('TASKS.DETAIL.STAGE'), value: props.stageName },
    { label: t('TASKS.DETAIL.CONTACT'), value: props.task?.contact?.name },
    { label: t('TASKS.DETAIL.OWNER'), value: props.task?.assignee?.name },
    { label: t('TASKS.DETAIL.ORIGIN'), value: crm.value.origin },
    {
      label: t('TASKS.DETAIL.EXPECTED_CLOSE'),
      value: formatDate(crm.value.expected_close_date),
    },
    {
      label: t('TASKS.DETAIL.STAGE_CHANGED'),
      value: formatDate(crm.value.stage_changed_at),
    },
    { label: t('TASKS.DETAIL.CREATED'), value: formatDate(crm.value.added_at) },
    { label: t('TASKS.DETAIL.LOST_REASON'), value: crm.value.lost_reason },
  ].filter(item => item.value)
);
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :show-confirm-button="false"
  >
    <div v-if="task" class="flex flex-col gap-5">
      <div class="flex flex-col gap-2">
        <div class="flex items-start gap-3">
          <h3 class="flex-1 text-lg font-medium leading-snug text-n-slate-12">
            {{ task.title }}
          </h3>
          <Avatar
            v-if="task.assignee"
            :name="task.assignee.name"
            :src="task.assignee.thumbnail"
            :size="28"
            rounded-full
          />
        </div>
        <div class="flex flex-wrap items-center gap-1.5">
          <span
            v-if="statusLabel"
            class="px-2 py-0.5 rounded-md text-[11px] font-medium"
            :class="statusTone"
          >
            {{ statusLabel }}
          </span>
          <span
            v-if="stageName"
            class="px-2 py-0.5 rounded-md text-[11px] font-medium bg-n-alpha-2 text-n-slate-11"
          >
            {{ stageName }}
          </span>
        </div>
      </div>

      <div v-if="money.length" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div
          v-for="item in money"
          :key="item.key"
          class="flex flex-col gap-1 p-3 border bg-n-solid-2 border-n-weak rounded-xl"
        >
          <span class="text-[11px] uppercase tracking-wide text-n-slate-10">
            {{ item.label }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ item.amount }}
          </span>
        </div>
      </div>

      <div class="grid gap-5 sm:grid-cols-2">
        <div v-if="fields.length" class="flex flex-col gap-3">
          <h4
            class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
          >
            {{ t('TASKS.DETAIL.FIELDS') }}
          </h4>
          <dl class="flex flex-col gap-2">
            <div
              v-for="field in fields"
              :key="field.name"
              class="flex items-start justify-between gap-3 pb-2 border-b border-n-weak last:border-0"
            >
              <dt class="text-xs text-n-slate-10">{{ field.name }}</dt>
              <dd class="text-xs font-medium text-right text-n-slate-12">
                {{ field.value }}
              </dd>
            </div>
          </dl>
        </div>

        <div class="flex flex-col gap-3">
          <h4
            class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
          >
            {{ t('TASKS.DETAIL.SUMMARY') }}
          </h4>
          <dl class="flex flex-col gap-2">
            <div
              v-for="item in summary"
              :key="item.label"
              class="flex items-start justify-between gap-3 pb-2 border-b border-n-weak last:border-0"
            >
              <dt class="text-xs text-n-slate-10">{{ item.label }}</dt>
              <dd class="text-xs font-medium text-right text-n-slate-12">
                {{ item.value }}
              </dd>
            </div>
          </dl>
        </div>
      </div>

      <p
        v-if="task.description"
        class="text-xs whitespace-pre-line text-n-slate-11"
      >
        {{ task.description }}
      </p>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          :label="t('TASKS.DETAIL.CLOSE')"
          type="button"
          @click="close"
        />
        <a
          v-if="crm.url"
          :href="crm.url"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90"
        >
          <span class="i-lucide-external-link size-4" />
          {{ t('TASKS.DETAIL.OPEN_IN_CRM') }}
        </a>
      </div>
    </template>
  </Dialog>
</template>
