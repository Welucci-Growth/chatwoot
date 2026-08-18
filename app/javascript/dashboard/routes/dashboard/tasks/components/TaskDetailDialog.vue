<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import TasksAPI from 'dashboard/api/tasks';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const props = defineProps({
  task: { type: Object, default: null },
  stageName: { type: String, default: '' },
});

const { t } = useI18n();

const FIELD_PREVIEW_COUNT = 12;

const dialogRef = ref(null);
const activeTab = ref(0);
const showAllFields = ref(false);
const isLoading = ref(false);
const hasFailed = ref(false);
const panel = ref({});
const previews = ref({});

const crm = computed(() => props.task?.customAttributes?.pipedrive || {});
const amounts = computed(() => crm.value.amounts || {});
const fields = computed(() => crm.value.fields || []);
const products = computed(() => panel.value.products || []);
const files = computed(() => panel.value.files || []);
const notes = computed(() => panel.value.notes || []);
const activities = computed(() => panel.value.activities || []);
const person = computed(() => panel.value.person || null);

const formatMoney = (value, currency) =>
  new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: currency || amounts.value.currency || 'BRL',
    maximumFractionDigits: 0,
  }).format(value);

const formatDate = value => (value ? new Date(value).toLocaleDateString() : '');

const formatSize = bytes => {
  if (!bytes) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  const exponent = Math.min(
    Math.floor(Math.log(bytes) / Math.log(1024)),
    units.length - 1
  );
  return `${(bytes / 1024 ** exponent).toFixed(exponent ? 1 : 0)} ${units[exponent]}`;
};

// Imagens do CRM exigem autenticacao, entao a previa vem por blob em vez de src direto.
const loadPreviews = async () => {
  await Promise.all(
    files.value
      .filter(file => file.image && !previews.value[file.id])
      .map(async file => {
        try {
          const { data } = await TasksAPI.crmFile(props.task.id, file.id);
          previews.value[file.id] = URL.createObjectURL(data);
        } catch {
          previews.value[file.id] = '';
        }
      })
  );
};

const downloadFile = async file => {
  const { data } = await TasksAPI.crmFile(props.task.id, file.id);
  const url = URL.createObjectURL(data);
  const link = document.createElement('a');
  link.href = url;
  link.download = file.name;
  link.click();
  URL.revokeObjectURL(url);
};

const loadPanel = async () => {
  isLoading.value = true;
  hasFailed.value = false;
  try {
    const { data } = await TasksAPI.crmPanel(props.task.id);
    panel.value = data;
    await loadPreviews();
  } catch {
    hasFailed.value = true;
  } finally {
    isLoading.value = false;
  }
};

const releasePreviews = () => {
  Object.values(previews.value).forEach(url => url && URL.revokeObjectURL(url));
  previews.value = {};
};

const open = () => {
  activeTab.value = 0;
  showAllFields.value = false;
  panel.value = {};
  releasePreviews();
  dialogRef.value.open();
  loadPanel();
};

const close = () => {
  releasePreviews();
  dialogRef.value.close();
};

defineExpose({ open, close });

const visibleFields = computed(() =>
  showAllFields.value
    ? fields.value
    : fields.value.slice(0, FIELD_PREVIEW_COUNT)
);
const hasHiddenFields = computed(
  () => fields.value.length > FIELD_PREVIEW_COUNT
);

const statusLabel = computed(
  () =>
    ({
      won: t('TASKS.DETAIL.STATUS.WON'),
      lost: t('TASKS.DETAIL.STATUS.LOST'),
      open: t('TASKS.DETAIL.STATUS.OPEN'),
    })[crm.value.status] || ''
);

const statusTone = computed(
  () =>
    ({
      won: 'bg-n-teal-3 text-n-teal-11',
      lost: 'bg-n-ruby-3 text-n-ruby-11',
    })[crm.value.status] || 'bg-n-alpha-2 text-n-slate-11'
);

const stats = computed(() =>
  [
    { key: 'value', label: t('TASKS.DETAIL.VALUE') },
    { key: 'mrr', label: t('TASKS.DETAIL.MRR') },
    { key: 'arr', label: t('TASKS.DETAIL.ARR') },
    { key: 'acv', label: t('TASKS.DETAIL.ACV') },
  ]
    .filter(item => Number(amounts.value[item.key]) > 0)
    .map(item => ({ ...item, amount: formatMoney(amounts.value[item.key]) }))
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

const productsTotal = computed(() =>
  products.value.reduce((total, product) => total + Number(product.sum || 0), 0)
);

// Abas vazias nao aparecem: o objetivo e justamente nao repetir o Pipedrive poluido.
const tabs = computed(() =>
  [
    { key: 'overview', label: t('TASKS.DETAIL.TABS.OVERVIEW') },
    {
      key: 'products',
      label: t('TASKS.DETAIL.TABS.PRODUCTS'),
      count: products.value.length,
    },
    {
      key: 'files',
      label: t('TASKS.DETAIL.TABS.FILES'),
      count: files.value.length,
    },
    {
      key: 'notes',
      label: t('TASKS.DETAIL.TABS.NOTES'),
      count: notes.value.length,
    },
    {
      key: 'activities',
      label: t('TASKS.DETAIL.TABS.ACTIVITIES'),
      count: activities.value.length,
    },
  ].filter(tab => tab.key === 'overview' || tab.count > 0)
);

const currentTab = computed(
  () => tabs.value[activeTab.value]?.key || 'overview'
);

// O TabBar emite a aba, nao o indice.
const onTabChange = tab => {
  activeTab.value = tabs.value.findIndex(item => item.key === tab.key);
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :show-confirm-button="false"
  >
    <div v-if="task" class="flex flex-col gap-5">
      <div class="flex flex-col gap-3">
        <div class="flex items-start gap-3">
          <div class="flex flex-col flex-1 gap-1.5 min-w-0">
            <h3 class="text-xl font-medium leading-tight text-n-slate-12">
              {{ task.title }}
            </h3>
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
              <span
                v-if="person?.organization"
                class="px-2 py-0.5 rounded-md text-[11px] font-medium bg-n-alpha-2 text-n-slate-11"
              >
                {{ person.organization }}
              </span>
            </div>
          </div>
          <Avatar
            v-if="task.assignee"
            :name="task.assignee.name"
            :src="task.assignee.thumbnail"
            :size="32"
            rounded-full
          />
        </div>

        <div v-if="stats.length" class="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <div
            v-for="stat in stats"
            :key="stat.key"
            class="flex flex-col gap-1 px-3 py-2.5 border bg-n-solid-2 border-n-weak rounded-xl"
          >
            <span class="text-[10px] uppercase tracking-wide text-n-slate-10">
              {{ stat.label }}
            </span>
            <span class="text-sm font-semibold truncate text-n-slate-12">
              {{ stat.amount }}
            </span>
          </div>
        </div>
      </div>

      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeTab"
        @tab-changed="onTabChange"
      />

      <div v-if="isLoading" class="flex items-center justify-center py-10">
        <Spinner />
      </div>

      <p v-else-if="hasFailed" class="py-6 text-xs text-center text-n-ruby-11">
        {{ t('TASKS.DETAIL.LOAD_ERROR') }}
      </p>

      <template v-else>
        <div v-if="currentTab === 'overview'" class="flex flex-col gap-5">
          <div
            v-if="summary.length"
            class="grid grid-cols-2 gap-3 sm:grid-cols-3"
          >
            <div
              v-for="item in summary"
              :key="item.label"
              class="flex flex-col gap-0.5 min-w-0"
            >
              <span class="text-[11px] text-n-slate-10">{{ item.label }}</span>
              <span class="text-xs font-medium truncate text-n-slate-12">
                {{ item.value }}
              </span>
            </div>
          </div>

          <div
            v-if="person?.emails?.length || person?.phones?.length"
            class="flex flex-wrap gap-2"
          >
            <a
              v-for="email in person.emails"
              :key="email"
              :href="`mailto:${email}`"
              class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:text-n-brand"
            >
              <span class="i-lucide-mail size-3.5" />
              {{ email }}
            </a>
            <a
              v-for="phone in person.phones"
              :key="phone"
              :href="`tel:${phone}`"
              class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:text-n-brand"
            >
              <span class="i-lucide-phone size-3.5" />
              {{ phone }}
            </a>
          </div>

          <div v-if="fields.length" class="flex flex-col gap-3">
            <h4
              class="text-xs font-medium tracking-wide uppercase text-n-slate-10"
            >
              {{ t('TASKS.DETAIL.FIELDS') }}
            </h4>
            <dl class="grid gap-x-6 gap-y-2 sm:grid-cols-2">
              <div
                v-for="field in visibleFields"
                :key="field.name"
                class="flex items-start justify-between gap-3 pb-2 border-b border-n-weak"
              >
                <dt class="text-xs text-n-slate-10">{{ field.name }}</dt>
                <dd class="text-xs font-medium text-right text-n-slate-12">
                  {{ field.value }}
                </dd>
              </div>
            </dl>
            <button
              v-if="hasHiddenFields"
              class="self-start text-xs font-medium text-n-brand hover:underline"
              type="button"
              @click="showAllFields = !showAllFields"
            >
              {{
                showAllFields
                  ? t('TASKS.DETAIL.SHOW_LESS')
                  : t('TASKS.DETAIL.SHOW_ALL', { count: fields.length })
              }}
            </button>
          </div>
        </div>

        <div v-else-if="currentTab === 'products'" class="flex flex-col gap-2">
          <div
            v-for="product in products"
            :key="product.name"
            class="flex items-center justify-between gap-3 px-3 py-2.5 border bg-n-solid-2 border-n-weak rounded-xl"
          >
            <div class="flex flex-col min-w-0 gap-0.5">
              <span class="text-xs font-medium truncate text-n-slate-12">
                {{ product.name }}
              </span>
              <span class="text-[11px] text-n-slate-10">
                {{
                  t('TASKS.DETAIL.QUANTITY_PRICE', {
                    quantity: product.quantity,
                    price: formatMoney(product.price, product.currency),
                  })
                }}
              </span>
            </div>
            <span class="text-xs font-semibold shrink-0 text-n-slate-12">
              {{ formatMoney(product.sum, product.currency) }}
            </span>
          </div>
          <div class="flex items-center justify-between px-3 pt-1">
            <span class="text-xs text-n-slate-10">
              {{ t('TASKS.DETAIL.TOTAL') }}
            </span>
            <span class="text-sm font-semibold text-n-slate-12">
              {{ formatMoney(productsTotal) }}
            </span>
          </div>
        </div>

        <div
          v-else-if="currentTab === 'files'"
          class="grid gap-3 sm:grid-cols-3"
        >
          <div
            v-for="file in files"
            :key="file.id"
            class="flex flex-col overflow-hidden border bg-n-solid-2 border-n-weak rounded-xl"
          >
            <img
              v-if="file.image && previews[file.id]"
              :src="previews[file.id]"
              :alt="file.name"
              class="object-cover w-full h-28"
            />
            <div
              v-else
              class="flex items-center justify-center w-full h-28 bg-n-alpha-2"
            >
              <span class="i-lucide-file-text size-6 text-n-slate-10" />
            </div>
            <div class="flex items-center gap-2 p-2.5">
              <div class="flex flex-col flex-1 min-w-0">
                <span class="text-[11px] font-medium truncate text-n-slate-12">
                  {{ file.name }}
                </span>
                <span class="text-[10px] text-n-slate-10">
                  {{ formatSize(file.size) }}
                </span>
              </div>
              <button
                class="flex items-center justify-center rounded-md shrink-0 size-7 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-brand"
                type="button"
                :title="t('TASKS.DETAIL.DOWNLOAD')"
                @click="downloadFile(file)"
              >
                <span class="i-lucide-download size-3.5" />
              </button>
            </div>
          </div>
        </div>

        <div v-else-if="currentTab === 'notes'" class="flex flex-col gap-2">
          <div
            v-for="note in notes"
            :key="note.id"
            class="flex flex-col gap-1.5 p-3 border bg-n-solid-2 border-n-weak rounded-xl"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-[11px] font-medium text-n-slate-11">
                {{ note.author }}
              </span>
              <span class="text-[10px] text-n-slate-10">
                {{ formatDate(note.added_at) }}
              </span>
            </div>
            <p class="text-xs whitespace-pre-line text-n-slate-12">
              {{ note.content }}
            </p>
          </div>
        </div>

        <div
          v-else-if="currentTab === 'activities'"
          class="flex flex-col gap-2"
        >
          <div
            v-for="activity in activities"
            :key="activity.id"
            class="flex items-start gap-3 px-3 py-2.5 border bg-n-solid-2 border-n-weak rounded-xl"
          >
            <span
              class="mt-0.5 size-3.5 shrink-0"
              :class="
                activity.done
                  ? 'i-lucide-check-circle-2 text-n-teal-11'
                  : 'i-lucide-clock text-n-slate-10'
              "
            />
            <div class="flex flex-col flex-1 min-w-0 gap-0.5">
              <span class="text-xs font-medium text-n-slate-12">
                {{ activity.subject }}
              </span>
              <span v-if="activity.note" class="text-[11px] text-n-slate-11">
                {{ activity.note }}
              </span>
            </div>
            <span class="text-[10px] shrink-0 text-n-slate-10">
              {{ formatDate(activity.due_date) }}
            </span>
          </div>
        </div>
      </template>
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
          class="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-white rounded-lg bg-n-brand hover:opacity-90"
        >
          <span class="i-lucide-external-link size-4" />
          {{ t('TASKS.DETAIL.OPEN_IN_CRM') }}
        </a>
      </div>
    </template>
  </Dialog>
</template>
