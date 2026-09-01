<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useAccount } from 'dashboard/composables/useAccount';
import { useI18n } from 'vue-i18n';
import TasksAPI from 'dashboard/api/tasks';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import ContactAPI from 'dashboard/api/contacts';

const props = defineProps({
  task: { type: Object, default: null },
  stageName: { type: String, default: '' },
});

const { t } = useI18n();

const FIELD_PREVIEW_COUNT = 12;

const { accountScopedRoute } = useAccount();
const store = useStore();

const dialogRef = ref(null);
const activeTab = ref(0);
const showAllFields = ref(false);
const isLoading = ref(false);
const hasFailed = ref(false);
const panel = ref({});
const conversations = ref([]);
const activeConversationId = ref(null);
const isLoadingConversations = ref(false);
const conversationsFailed = ref(false);
const previews = ref({});

// Cards can come from either CRM. HubSpot cards carry everything they need already, so the
// dialog reads them straight from the card instead of calling the CRM when it opens.
const source = computed(() =>
  props.task?.customAttributes?.hubspot ? 'hubspot' : 'pipedrive'
);
const isHubspot = computed(() => source.value === 'hubspot');
const crm = computed(() => props.task?.customAttributes?.[source.value] || {});
const amounts = computed(() => crm.value.amounts || {});
const fields = computed(() => crm.value.fields || []);
const products = computed(() => panel.value.products || []);
const files = computed(() => panel.value.files || []);
const notes = computed(() => panel.value.notes || []);
const activities = computed(() => panel.value.activities || []);
const person = computed(() => panel.value.person || null);
const stages = computed(() => panel.value.stages || []);
const changelog = computed(() => panel.value.changelog || []);

const pendingActivities = computed(() =>
  activities.value.filter(activity => !activity.done)
);
const doneActivities = computed(() =>
  activities.value.filter(activity => activity.done)
);

const isOverdue = activity =>
  activity.due_date && new Date(activity.due_date) < new Date();

const activityGroups = computed(() =>
  [
    {
      key: 'pending',
      label: t('TASKS.DETAIL.PENDING'),
      items: pendingActivities.value,
    },
    { key: 'done', label: t('TASKS.DETAIL.DONE'), items: doneActivities.value },
  ].filter(group => group.items.length)
);

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

// O download do Pipedrive volta como octet-stream, entao o tipo vem do nome do arquivo.
const imageMimeType = name => {
  const extension = name.split('.').pop().toLowerCase();
  return `image/${extension === 'jpg' ? 'jpeg' : extension}`;
};

// Imagens do CRM exigem autenticacao, entao a previa vem por blob em vez de src direto.
const loadPreviews = async () => {
  await Promise.all(
    files.value
      .filter(file => file.image && !previews.value[file.id])
      .map(async file => {
        try {
          const { data } = await TasksAPI.crmFile(props.task.id, file.id);
          previews.value[file.id] = URL.createObjectURL(
            new Blob([data], { type: imageMimeType(file.name) })
          );
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
  conversations.value = [];
  activeConversationId.value = null;
  conversationsFailed.value = false;
  showAllFields.value = isHubspot.value;
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

// HubSpot has no single status field; the outcome shows up as the closed flag, a lost
// reason, or simply the stage the deal sits in.
const hubspotStatus = computed(() => {
  const c = crm.value;
  const stage = (props.task?.taskColumn?.name || '').toUpperCase();
  if (c.closed_won === 'true' || stage === 'GANHO') return 'won';
  if (c.lost_reason || stage === 'PERDIDO') return 'lost';
  return 'open';
});

const statusLabel = computed(
  () =>
    ({
      won: t('TASKS.DETAIL.STATUS.WON'),
      lost: t('TASKS.DETAIL.STATUS.LOST'),
      open: t('TASKS.DETAIL.STATUS.OPEN'),
    })[isHubspot.value ? hubspotStatus.value : crm.value.status] || ''
);

const statusTone = computed(
  () =>
    ({
      won: 'bg-n-teal-3 text-n-teal-11',
      lost: 'bg-n-ruby-3 text-n-ruby-11',
    })[isHubspot.value ? hubspotStatus.value : crm.value.status] ||
    'bg-n-alpha-2 text-n-slate-11'
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

const legacyTabs = computed(() =>
  [
    { key: 'overview', label: t('TASKS.DETAIL.TABS.OVERVIEW') },
    {
      key: 'activities',
      label: t('TASKS.DETAIL.TABS.ACTIVITIES'),
      count: activities.value.length,
    },
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
      key: 'changelog',
      label: t('TASKS.DETAIL.TABS.HISTORY'),
      count: changelog.value.length,
    },
  ].filter(tab => tab.key === 'overview' || tab.count > 0)
);

// Abas vazias nao aparecem: o objetivo e justamente nao repetir o Pipedrive poluido.
const crmTabs = computed(() =>
  isHubspot.value
    ? [{ key: 'overview', label: t('TASKS.DETAIL.TABS.OVERVIEW') }]
    : legacyTabs.value
);

// Everything below comes from the card itself. Rows with no value are dropped, so the panel
// shows what this deal actually has rather than a grid of blanks.
// The mirror links the card to a Chatwoot contact when it can match by email or phone.
// Where that worked, the agent can jump straight to the person and their conversations.
const linkedContact = computed(() => props.task?.contact || null);

const contactRoute = computed(() =>
  linkedContact.value
    ? accountScopedRoute('contacts_edit', { contactId: linkedContact.value.id })
    : null
);

const tabs = computed(() =>
  linkedContact.value
    ? [
        ...crmTabs.value,
        { key: 'conversation', label: t('TASKS.DETAIL.TABS.CONVERSATION') },
      ]
    : crmTabs.value
);

const inboxName = conversation =>
  store.getters['inboxes/getInbox'](conversation.inbox_id)?.name || '';

// The thread is the standard conversation pane, so the agent reads and answers the client
// with the same tools as the inbox instead of a read-only copy of the history.
const openConversation = async conversationId => {
  activeConversationId.value = null;
  await store.dispatch('getConversation', conversationId);
  const conversation = store.getters.getConversationById(conversationId);
  if (!conversation) return;

  await store.dispatch('setActiveChat', { data: conversation });
  activeConversationId.value = conversationId;
};

// Loaded only when the tab is opened: most card views never need it.
const loadConversations = async () => {
  if (!linkedContact.value || isLoadingConversations.value) return;

  isLoadingConversations.value = true;
  conversationsFailed.value = false;
  try {
    const { data } = await ContactAPI.getConversations(linkedContact.value.id);
    conversations.value = [...data.payload].sort(
      (a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0)
    );
    if (conversations.value.length) {
      await openConversation(conversations.value[0].id);
    }
  } catch (error) {
    conversationsFailed.value = true;
  } finally {
    isLoadingConversations.value = false;
  }
};

const summaryRows = computed(() => {
  if (!isHubspot.value) return [];
  const c = crm.value;
  return [
    {
      key: 'stage',
      label: t('TASKS.DETAIL.HUBSPOT.STAGE'),
      value: props.task?.taskColumn?.name,
    },
    {
      key: 'amount',
      label: t('TASKS.DETAIL.HUBSPOT.AMOUNT'),
      value: amounts.value.value ? formatMoney(amounts.value.value) : null,
    },
    { key: 'type', label: t('TASKS.DETAIL.HUBSPOT.TYPE'), value: c.deal_type },
    {
      key: 'owner',
      label: t('TASKS.DETAIL.HUBSPOT.OWNER'),
      value: props.task?.assignee?.name,
    },
    {
      key: 'close',
      label: t('TASKS.DETAIL.HUBSPOT.CLOSE_DATE'),
      value: formatDate(c.close_date) || null,
    },
    {
      key: 'created',
      label: t('TASKS.DETAIL.HUBSPOT.CREATED'),
      value: formatDate(c.added_at) || null,
    },
    {
      key: 'updated',
      label: t('TASKS.DETAIL.HUBSPOT.UPDATED'),
      value: formatDate(c.updated_at) || null,
    },
    {
      key: 'lost',
      label: t('TASKS.DETAIL.HUBSPOT.LOST_REASON'),
      value: c.lost_reason,
    },
    {
      key: 'deal_id',
      label: t('TASKS.DETAIL.HUBSPOT.DEAL_ID'),
      value: c.deal_id,
    },
  ].filter(
    row => row.value !== null && row.value !== undefined && row.value !== ''
  );
});

const currentTab = computed(
  () => tabs.value[activeTab.value]?.key || 'overview'
);

watch(currentTab, tab => {
  if (tab === 'conversation' && !conversations.value.length)
    loadConversations();
});

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
      <div v-if="stages.length" class="flex gap-1 overflow-x-auto">
        <div
          v-for="stage in stages"
          :key="stage.name"
          class="flex flex-col gap-1 flex-1 min-w-[76px]"
        >
          <span
            class="h-1.5 rounded-full"
            :class="stage.current ? 'bg-n-brand' : 'bg-n-alpha-2'"
          />
          <span
            class="text-[10px] truncate"
            :class="
              stage.current
                ? 'font-semibold text-n-slate-12'
                : 'text-n-slate-10'
            "
          >
            {{ stage.name }}
          </span>
          <span v-if="stage.days" class="text-[10px] text-n-slate-10">
            {{ t('TASKS.DETAIL.DAYS', { count: stage.days }) }}
          </span>
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

          <router-link
            v-if="contactRoute"
            :to="contactRoute"
            class="inline-flex items-center self-start gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-n-brand text-white hover:opacity-90"
            @click="close"
          >
            <span class="i-lucide-user-round size-3.5" />
            {{ t('TASKS.DETAIL.OPEN_CONTACT', { name: linkedContact.name }) }}
          </router-link>

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

          <div v-if="summaryRows.length" class="flex flex-col gap-3">
            <h4
              class="text-xs font-medium tracking-wide uppercase text-n-slate-10"
            >
              {{ t('TASKS.DETAIL.HUBSPOT.SUMMARY') }}
            </h4>
            <dl class="grid gap-x-6 gap-y-2 sm:grid-cols-2">
              <div
                v-for="row in summaryRows"
                :key="row.key"
                class="flex flex-col gap-0.5 py-1.5 border-b border-n-weak"
              >
                <dt class="text-xs text-n-slate-10">{{ row.label }}</dt>
                <dd class="text-sm break-words text-n-slate-12">
                  {{ row.value }}
                </dd>
              </div>
            </dl>
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

        <div
          v-else-if="currentTab === 'conversation'"
          class="flex flex-col gap-3"
        >
          <div
            v-if="isLoadingConversations"
            class="flex items-center justify-center py-10"
          >
            <Spinner />
          </div>

          <p
            v-else-if="conversationsFailed"
            class="py-6 text-xs text-center text-n-ruby-11"
          >
            {{ t('TASKS.DETAIL.CONVERSATION_ERROR') }}
          </p>

          <p
            v-else-if="!conversations.length"
            class="py-6 text-xs text-center text-n-slate-11"
          >
            {{
              t('TASKS.DETAIL.CONVERSATION_EMPTY', { name: linkedContact.name })
            }}
          </p>

          <template v-else>
            <div v-if="conversations.length > 1" class="flex flex-wrap gap-1.5">
              <button
                v-for="conversation in conversations"
                :key="conversation.id"
                class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-lg"
                :class="
                  conversation.id === activeConversationId
                    ? 'bg-n-brand text-white'
                    : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-brand'
                "
                @click="openConversation(conversation.id)"
              >
                <span class="i-lucide-message-square size-3" />
                {{ inboxName(conversation) || `#${conversation.id}` }}
              </button>
            </div>

            <div
              class="flex flex-col overflow-hidden border rounded-lg h-[60vh] min-h-96 border-n-weak"
            >
              <ConversationBox
                v-if="activeConversationId"
                class="flex-grow min-h-0"
                :inbox-id="0"
                :is-contact-panel-open="false"
                :is-on-expanded-layout="false"
              />
            </div>
          </template>
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
          class="flex flex-col gap-4"
        >
          <div
            v-for="group in activityGroups"
            :key="group.key"
            class="flex flex-col gap-2"
          >
            <h4
              class="text-xs font-medium tracking-wide uppercase text-n-slate-10"
            >
              {{ group.label }}
            </h4>
            <div
              v-for="activity in group.items"
              :key="activity.id"
              class="flex items-start gap-3 px-3 py-2.5 border bg-n-solid-2 border-n-weak rounded-xl"
              :class="{ 'opacity-70': activity.done }"
            >
              <span
                class="mt-0.5 size-4 shrink-0"
                :class="
                  activity.done
                    ? 'i-lucide-check-circle-2 text-n-teal-11'
                    : 'i-lucide-circle text-n-slate-10'
                "
              />
              <div class="flex flex-col flex-1 min-w-0 gap-1">
                <span class="text-xs font-medium text-n-slate-12">
                  {{ activity.subject }}
                </span>
                <div class="flex flex-wrap items-center gap-2">
                  <span
                    v-if="activity.type"
                    class="px-1.5 py-0.5 rounded text-[10px] bg-n-alpha-2 text-n-slate-11"
                  >
                    {{ activity.type }}
                  </span>
                  <span
                    v-if="activity.owner"
                    class="text-[10px] text-n-slate-10"
                  >
                    {{ activity.owner }}
                  </span>
                </div>
                <span v-if="activity.note" class="text-[11px] text-n-slate-11">
                  {{ activity.note }}
                </span>
              </div>
              <span
                class="text-[10px] shrink-0"
                :class="
                  !activity.done && isOverdue(activity)
                    ? 'font-medium text-n-ruby-11'
                    : 'text-n-slate-10'
                "
              >
                {{ formatDate(activity.due_date) }}
              </span>
            </div>
          </div>
        </div>

        <div v-else-if="currentTab === 'changelog'" class="flex flex-col gap-2">
          <div
            v-for="(entry, index) in changelog"
            :key="index"
            class="flex items-start justify-between gap-3 pb-2 border-b border-n-weak"
          >
            <div class="flex flex-col min-w-0 gap-0.5">
              <span class="text-xs font-medium text-n-slate-12">
                {{ entry.field }}
              </span>
              <span class="text-[11px] text-n-slate-10">
                {{
                  t('TASKS.DETAIL.CHANGED', {
                    from: entry.from || '—',
                    to: entry.to || '—',
                  })
                }}
              </span>
            </div>
            <span class="text-[10px] shrink-0 text-n-slate-10">
              {{ formatDate(entry.changed_at) }}
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
