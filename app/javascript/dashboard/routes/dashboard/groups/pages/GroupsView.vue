<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useStore } from 'vuex';
import EvolutionGroupsAPI from 'dashboard/api/evolutionGroups';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { useMapGetter } from 'dashboard/composables/store';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useGroupTeam } from 'dashboard/composables/useGroupTeam';
import { useAdmin } from 'dashboard/composables/useAdmin';

const props = defineProps({
  filter: {
    type: String,
    default: 'all',
  },
});

const { t } = useI18n();
const store = useStore();
// Agents only follow groups; refreshing the directory and changing a group stay with admins.
const { isAdmin } = useAdmin();

const groups = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const lastSyncedAt = ref(null);
const isRefreshing = ref(false);
const search = ref('');
const instanceFilter = ref('');

const selected = ref(null);
const details = ref(null);
const isLoadingDetails = ref(false);
const showSettings = ref(false);
const draftSubject = ref('');
const draftDescription = ref('');

// Up to two hours a waiting client shows amber; past that, red.
const LATE_AFTER_MINUTES = 120;
const ownerFilter = ref('all');
const labelFilter = ref('');
const currentUserId = useMapGetter('getCurrentUserID');
const accountLabels = useMapGetter('labels/getLabels');
const getAssignableAgents = useMapGetter(
  'inboxAssignableAgents/getAssignableAgents'
);

const waitingMinutes = group =>
  group.status === 'waiting' && group.waiting_since
    ? Math.floor((Date.now() - new Date(group.waiting_since)) / 60000)
    : 0;
const isLate = group => waitingMinutes(group) >= LATE_AFTER_MINUTES;

const instanceNames = ref([]);
const instances = computed(() => [...instanceNames.value].sort());

const filtered = computed(() =>
  groups.value.filter(g => {
    const matchesName = (g.subject || '')
      .toLowerCase()
      .includes(search.value.toLowerCase());
    const matchesInstance =
      !instanceFilter.value || g.instance === instanceFilter.value;
    const matchesFilter =
      props.filter === 'all' ||
      (props.filter === 'active' && Boolean(g.conversation_id)) ||
      (props.filter === 'idle' && !g.conversation_id);
    const matchesOwner =
      ownerFilter.value === 'all' ||
      (ownerFilter.value === 'mine' &&
        g.assignee?.id === currentUserId.value) ||
      (ownerFilter.value === 'unassigned' &&
        Boolean(g.conversation_id) &&
        !g.assignee) ||
      g.assignee?.id === ownerFilter.value;
    const matchesLabel =
      !labelFilter.value || (g.labels || []).includes(labelFilter.value);
    return (
      matchesName &&
      matchesInstance &&
      matchesFilter &&
      matchesOwner &&
      matchesLabel
    );
  })
);

const WAITING_FIRST = { waiting: 0, answered: 1, idle: 2 };

// Waiting groups rise to the top and the longest wait leads, so the list answers "what needs
// me right now" without anyone having to sort it.
const ordered = computed(() =>
  [...filtered.value].sort((a, b) => {
    const rank = WAITING_FIRST[a.status] - WAITING_FIRST[b.status];
    if (rank !== 0) return rank;
    if (a.status === 'waiting') {
      return new Date(a.waiting_since) - new Date(b.waiting_since);
    }
    return (
      new Date(b.last_activity_at || 0) - new Date(a.last_activity_at || 0)
    );
  })
);

// Who holds which groups and how many clients wait on each, so the team can spread the load.
const ownerSummary = computed(() => {
  const rows = new Map();
  groups.value
    .filter(g => g.conversation_id)
    .forEach(g => {
      const key = g.assignee?.id ?? 'unassigned';
      const row = rows.get(key) || {
        id: key,
        name: g.assignee?.name || t('GROUPS.SUMMARY.UNASSIGNED'),
        total: 0,
        waiting: 0,
        late: 0,
      };
      row.total += 1;
      if (g.status === 'waiting') row.waiting += 1;
      if (isLate(g)) row.late += 1;
      rows.set(key, row);
    });
  return [...rows.values()].sort(
    (a, b) => b.late - a.late || b.waiting - a.waiting || b.total - a.total
  );
});

const lateCount = computed(() => groups.value.filter(isLate).length);

const labelOptions = computed(() =>
  [...new Set(groups.value.flatMap(g => g.labels || []))].sort()
);

const accountLabelOptions = computed(() =>
  (accountLabels.value || []).map(label => ({
    value: label.title,
    label: label.title,
  }))
);

const waitingLabel = group => {
  if (!group.waiting_since) return '';
  const minutes = waitingMinutes(group);
  if (minutes < 60) return `${minutes}min`;
  const hours = Math.floor(minutes / 60);
  return hours < 24 ? `${hours}h` : `${Math.floor(hours / 24)}d`;
};

const heading = computed(() => {
  if (props.filter === 'active') return t('GROUPS.MENU.ACTIVE');
  if (props.filter === 'idle') return t('GROUPS.MENU.IDLE');
  return t('GROUPS.TITLE');
});

// Each instance is fetched on its own so the table fills in progressively and one slow
// number never blocks the rest.
// Groups are stored, so opening the page is one fast request. Refreshing happens in the
// background and the list is repopulated when it finishes.
const loadGroups = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await EvolutionGroupsAPI.getGroups();
    groups.value = data.groups || [];
    instanceNames.value = [...new Set(groups.value.map(g => g.instance))];
    lastSyncedAt.value = data.last_synced_at;
  } catch (error) {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const requestRefresh = async () => {
  isRefreshing.value = true;
  await EvolutionGroupsAPI.refresh();
  useAlert(t('GROUPS.REFRESH_STARTED'));
  // The sync walks every number, so give it room before pulling the new directory.
  setTimeout(() => {
    loadGroups();
    isRefreshing.value = false;
  }, 120000);
};

const activeConversationId = ref(null);

const peers = computed(() =>
  selected.value?.inbox_id
    ? getAssignableAgents.value(selected.value.inbox_id)
    : []
);

// The list feeds the summary and the table, so a change made here shows up everywhere at once.
const updateGroup = (jid, changes) => {
  groups.value = groups.value.map(g =>
    g.jid === jid ? { ...g, ...changes } : g
  );
  if (selected.value?.jid === jid) {
    selected.value = { ...selected.value, ...changes };
  }
};

watch(
  () => selected.value?.inbox_id,
  inboxId => {
    if (inboxId) store.dispatch('inboxAssignableAgents/fetch', [inboxId]);
  }
);

const assignOwner = async event => {
  const agentId = Number(event.target.value) || 0;
  await store.dispatch('assignAgent', {
    conversationId: selected.value.conversation_id,
    agentId,
  });
  const agent = peers.value.find(a => a.id === agentId);
  updateGroup(selected.value.jid, {
    assignee: agent
      ? { id: agent.id, name: agent.available_name || agent.name }
      : null,
  });
};

const updateLabels = async labels => {
  const conversationId = selected.value.conversation_id;
  const jid = selected.value.jid;
  await store.dispatch('conversationLabels/update', {
    conversationId,
    labels,
  });
  updateGroup(jid, { labels: [...labels] });
};

// Groups that have already spoken have a real Chatwoot conversation, so the thread is the
// standard conversation pane rather than a second chat implementation.
const openConversation = async group => {
  activeConversationId.value = null;
  if (!group.conversation_id) return;

  await store.dispatch('getConversation', group.conversation_id);
  const conversation = store.getters.getConversationById(group.conversation_id);
  if (!conversation) return;

  await store.dispatch('setActiveChat', { data: conversation });
  activeConversationId.value = group.conversation_id;
};

const openGroup = async group => {
  selected.value = group;
  openConversation(group);
  if (!isAdmin.value) return;
  details.value = null;
  draftSubject.value = group.subject || '';
  draftDescription.value = group.description || '';
  isLoadingDetails.value = true;
  try {
    const { data } = await EvolutionGroupsAPI.getDetails(
      group.instance,
      group.jid
    );
    details.value = data;
  } catch (error) {
    useAlert(t('GROUPS.ERROR'));
  } finally {
    isLoadingDetails.value = false;
  }
};

const inviteLink = computed(() =>
  details.value?.invite_code
    ? `https://chat.whatsapp.com/${details.value.invite_code}`
    : ''
);

const copyInvite = () => {
  copyTextToClipboard(inviteLink.value);
  useAlert(t('GROUPS.DETAIL.COPIED'));
};

const revokeInvite = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('GROUPS.DETAIL.REVOKE_CONFIRM'))) return;
  const { data } = await EvolutionGroupsAPI.revokeInvite(
    selected.value.instance,
    selected.value.jid
  );
  details.value = { ...details.value, invite_code: data.invite_code };
};

const saveGroup = async () => {
  await EvolutionGroupsAPI.updateGroup(
    selected.value.instance,
    selected.value.jid,
    { subject: draftSubject.value, description: draftDescription.value }
  );
  selected.value.subject = draftSubject.value;
  selected.value.description = draftDescription.value;
  useAlert(t('GROUPS.DETAIL.SAVED'));
};

const toggleAdmin = async participant => {
  const actionType = participant.admin ? 'demote' : 'promote';
  await EvolutionGroupsAPI.updateAdmin(
    selected.value.instance,
    selected.value.jid,
    participant.id,
    actionType
  );
  participant.admin = participant.admin ? null : 'admin';
};

const displayNumber = id => `+${String(id).split('@')[0]}`;

const { loadTeam, isTeamMember } = useGroupTeam();

// The websocket already carries every new message to the dashboard, so the monitor updates
// itself instead of waiting for the next cache refresh.
const onMessageCreated = message => {
  const index = groups.value.findIndex(
    g => g.conversation_id === message.conversation_id
  );
  if (index === -1) return;

  const participant = message.content_attributes?.group_participant;
  // message_type arrives as the numeric enum over the socket, but tolerate the label too.
  const isOutgoing =
    message.message_type === 1 || message.message_type === 'outgoing';
  const fromTeam = isOutgoing || isTeamMember(participant?.phone_number);

  const updated = {
    ...groups.value[index],
    message_count: (groups.value[index].message_count || 0) + 1,
    last_activity_at: message.created_at,
    status: fromTeam ? 'answered' : 'waiting',
    waiting_since: fromTeam ? null : new Date().toISOString(),
    waiting_from: fromTeam ? null : participant?.name,
  };

  groups.value = [
    ...groups.value.slice(0, index),
    updated,
    ...groups.value.slice(index + 1),
  ];
};

onMounted(() => {
  loadTeam();
  loadGroups();
  emitter.on(BUS_EVENTS.MESSAGE_CREATED, onMessageCreated);
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.MESSAGE_CREATED, onMessageCreated);
});
</script>

<template>
  <div class="flex w-full h-full overflow-hidden">
    <div class="flex flex-col flex-grow h-full min-w-0 p-6 overflow-auto">
      <div class="flex flex-wrap items-start justify-between gap-3 mb-6">
        <div>
          <h1 class="text-lg font-medium text-n-slate-12">
            {{ heading }}
          </h1>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ $t('GROUPS.SUBTITLE') }}
          </p>
          <p
            v-if="lateCount"
            class="inline-block px-2 py-0.5 mt-2 text-xs font-medium rounded-full bg-n-ruby-3 text-n-ruby-11"
          >
            {{ $t('GROUPS.LATE_COUNT', { count: lateCount }) }}
          </p>
        </div>
        <NextButton
          v-if="isAdmin"
          sm
          faded
          slate
          icon="i-lucide-refresh-cw"
          :is-loading="isRefreshing"
          :label="$t('GROUPS.REFRESH')"
          @click="requestRefresh"
        />
      </div>

      <div v-if="ownerSummary.length" class="flex flex-wrap gap-2 mb-4">
        <button
          v-for="row in ownerSummary"
          :key="row.id"
          type="button"
          class="flex flex-col items-start px-3 py-2 text-left border rounded-lg border-n-weak hover:bg-n-slate-2"
          :class="{ 'bg-n-slate-2': ownerFilter === row.id }"
          @click="ownerFilter = ownerFilter === row.id ? 'all' : row.id"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ row.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              $t('GROUPS.SUMMARY.LINE', {
                total: row.total,
                waiting: row.waiting,
              })
            }}
            <span v-if="row.late" class="font-medium text-n-ruby-11">
              {{ $t('GROUPS.SUMMARY.LATE', { count: row.late }) }}
            </span>
          </span>
        </button>
      </div>

      <div class="flex flex-wrap gap-3 mb-4">
        <select v-model="ownerFilter" class="w-48 mb-0">
          <option value="all">{{ $t('GROUPS.OWNER_FILTER.ALL') }}</option>
          <option value="mine">{{ $t('GROUPS.OWNER_FILTER.MINE') }}</option>
          <option value="unassigned">
            {{ $t('GROUPS.OWNER_FILTER.UNASSIGNED') }}
          </option>
          <option
            v-for="row in ownerSummary.filter(r => r.id !== 'unassigned')"
            :key="row.id"
            :value="row.id"
          >
            {{ row.name }}
          </option>
        </select>
        <select v-model="labelFilter" class="w-48 mb-0">
          <option value="">{{ $t('GROUPS.LABEL_FILTER_ALL') }}</option>
          <option v-for="label in labelOptions" :key="label" :value="label">
            {{ label }}
          </option>
        </select>
        <input
          v-model="search"
          type="text"
          class="w-64 mb-0"
          :placeholder="$t('GROUPS.SEARCH_PLACEHOLDER')"
        />
        <select v-model="instanceFilter" class="w-56 mb-0">
          <option value="">{{ $t('GROUPS.ALL_NUMBERS') }}</option>
          <option v-for="name in instances" :key="name" :value="name">
            {{ name }}
          </option>
        </select>
        <span class="self-center text-sm text-n-slate-11">
          {{ $t('GROUPS.COUNT', { count: filtered.length }) }}
        </span>
      </div>

      <p v-if="isLoading" class="text-sm text-n-slate-11">
        {{ $t('GROUPS.LOADING') }}
      </p>
      <p v-if="hasError" class="mb-3 text-sm text-n-ruby-11">
        {{ $t('GROUPS.ERROR') }}
      </p>
      <p v-else-if="!filtered.length" class="text-sm text-n-slate-11">
        {{ $t('GROUPS.EMPTY') }}
      </p>

      <div
        v-if="filtered.length"
        class="overflow-x-auto border rounded-lg border-n-weak"
      >
        <table class="w-full text-sm">
          <thead class="bg-n-slate-2">
            <tr class="text-left text-n-slate-11">
              <th class="px-4 py-2 font-medium">
                {{ $t('GROUPS.TABLE.NAME') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ $t('GROUPS.TABLE.NUMBER') }}
              </th>
              <th class="px-4 py-2 font-medium tabular-nums">
                {{ $t('GROUPS.TABLE.PARTICIPANTS') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ $t('GROUPS.TABLE.ANNOUNCE') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ $t('GROUPS.TABLE.STATUS') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ $t('GROUPS.TABLE.OWNER') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ $t('GROUPS.TABLE.LABELS') }}
              </th>
              <th class="px-4 py-2 font-medium">
                {{ $t('GROUPS.TABLE.ACTIVITY') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="group in ordered"
              :key="group.jid"
              class="border-t cursor-pointer border-n-weak hover:bg-n-slate-2"
              @click="openGroup(group)"
            >
              <td class="px-4 py-2 text-n-slate-12">{{ group.subject }}</td>
              <td class="px-4 py-2 text-n-slate-11">{{ group.instance }}</td>
              <td class="px-4 py-2 tabular-nums text-n-slate-11">
                {{ group.size }}
              </td>
              <td class="px-4 py-2 text-n-slate-11">
                <span
                  v-if="group.announce_only"
                  class="inline-block size-4 i-lucide-check text-n-teal-11"
                  :title="$t('GROUPS.TABLE.ANNOUNCE')"
                />
              </td>
              <td class="px-4 py-2">
                <span
                  v-if="group.status === 'waiting'"
                  class="px-2 py-0.5 text-xs rounded-full whitespace-nowrap"
                  :class="
                    isLate(group)
                      ? 'bg-n-ruby-3 text-n-ruby-11'
                      : 'bg-n-amber-3 text-n-amber-11'
                  "
                >
                  {{
                    $t('GROUPS.STATUS.WAITING_FOR', {
                      duration: waitingLabel(group),
                    })
                  }}
                </span>
                <span
                  v-else-if="group.status === 'answered'"
                  class="px-2 py-0.5 text-xs rounded-full bg-n-teal-3 text-n-teal-11"
                >
                  {{ $t('GROUPS.STATUS.ANSWERED') }}
                </span>
                <span v-else class="text-xs text-n-slate-10">
                  {{ $t('GROUPS.STATUS.IDLE') }}
                </span>
              </td>
              <td class="px-4 py-2 text-n-slate-11 whitespace-nowrap">
                {{ group.assignee?.name || '—' }}
              </td>
              <td class="px-4 py-2">
                <span class="flex flex-wrap gap-1">
                  <span
                    v-for="label in group.labels || []"
                    :key="label"
                    class="px-1.5 py-0.5 text-xs rounded bg-n-slate-3 text-n-slate-11"
                  >
                    {{ label }}
                  </span>
                </span>
              </td>
              <td class="px-4 py-2 text-n-slate-11">
                <span
                  v-if="group.conversation_id"
                  class="flex items-center gap-2"
                >
                  <span class="tabular-nums">{{ group.message_count }}</span>
                  <span
                    v-if="group.unread_count"
                    class="px-1.5 py-0.5 text-xs rounded-full bg-n-teal-9 text-white tabular-nums"
                  >
                    {{ group.unread_count }}
                  </span>
                </span>
                <span v-else class="text-xs text-n-slate-10">
                  {{ $t('GROUPS.TABLE.NO_THREAD') }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <aside
      v-if="selected"
      class="flex flex-col flex-shrink-0 h-full border-l w-[32rem] border-n-weak"
    >
      <div
        class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
      >
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ selected.subject }}
        </span>
        <div class="flex items-center gap-1">
          <NextButton
            v-if="isAdmin"
            xs
            ghost
            slate
            icon="i-lucide-settings-2"
            :aria-label="$t('GROUPS.DETAIL.TITLE')"
            @click="showSettings = !showSettings"
          />
          <NextButton
            xs
            ghost
            slate
            icon="i-lucide-x"
            :aria-label="$t('GROUPS.DETAIL.CLOSE')"
            @click="selected = null"
          />
        </div>
      </div>

      <div
        v-if="selected.conversation_id && !showSettings"
        class="flex flex-col gap-3 px-4 py-3 border-b border-n-weak"
      >
        <label class="flex items-center gap-2 mb-0 text-sm text-n-slate-11">
          <span class="w-24 shrink-0">{{
            $t('GROUPS.DETAIL.OWNER_LABEL')
          }}</span>
          <select
            class="mb-0"
            :value="selected.assignee?.id || 0"
            @change="assignOwner"
          >
            <option :value="0">{{ $t('GROUPS.DETAIL.NO_OWNER') }}</option>
            <option v-for="agent in peers" :key="agent.id" :value="agent.id">
              {{ agent.available_name || agent.name }}
            </option>
          </select>
        </label>
        <div class="flex items-start gap-2 text-sm text-n-slate-11">
          <span class="w-24 pt-2 shrink-0">
            {{ $t('GROUPS.DETAIL.LABELS') }}
          </span>
          <TagMultiSelectComboBox
            class="flex-1"
            :model-value="[...(selected.labels || [])]"
            :options="accountLabelOptions"
            :placeholder="$t('GROUPS.DETAIL.LABELS_PLACEHOLDER')"
            @update:model-value="updateLabels"
          />
        </div>
      </div>

      <div v-if="showSettings" class="flex flex-col gap-4 p-4 overflow-auto">
        <label>
          {{ $t('GROUPS.TABLE.NAME') }}
          <input v-model="draftSubject" type="text" />
        </label>

        <label>
          {{ $t('GROUPS.DETAIL.DESCRIPTION') }}
          <textarea v-model="draftDescription" rows="3" />
        </label>

        <NextButton
          sm
          class="w-fit"
          :label="$t('GROUPS.DETAIL.SAVE')"
          @click="saveGroup"
        />

        <div v-if="isLoadingDetails" class="text-sm text-n-slate-11">
          {{ $t('GROUPS.LOADING') }}
        </div>

        <template v-else-if="details">
          <div class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('GROUPS.DETAIL.INVITE') }}
            </span>
            <code
              class="p-2 overflow-x-auto text-xs rounded bg-n-slate-2 text-n-slate-12"
            >
              {{ inviteLink }}
            </code>
            <div class="flex gap-2">
              <NextButton
                xs
                faded
                slate
                :label="$t('GROUPS.DETAIL.COPY')"
                @click="copyInvite"
              />
              <NextButton
                xs
                faded
                ruby
                :label="$t('GROUPS.DETAIL.REVOKE')"
                @click="revokeInvite"
              />
            </div>
          </div>

          <div class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('GROUPS.DETAIL.PARTICIPANTS') }}
            </span>
            <div
              v-for="p in details.participants"
              :key="p.id"
              class="flex items-center justify-between gap-2 py-1"
            >
              <span class="flex items-center gap-2 text-sm text-n-slate-11">
                {{ displayNumber(p.id) }}
                <span
                  v-if="p.admin"
                  class="px-1.5 py-0.5 text-xs rounded bg-n-slate-3 text-n-slate-11"
                >
                  {{
                    p.admin === 'superadmin'
                      ? $t('GROUPS.DETAIL.OWNER')
                      : $t('GROUPS.DETAIL.ADMIN')
                  }}
                </span>
              </span>
              <NextButton
                v-if="p.admin !== 'superadmin'"
                xs
                ghost
                slate
                :label="
                  p.admin
                    ? $t('GROUPS.DETAIL.DEMOTE')
                    : $t('GROUPS.DETAIL.PROMOTE')
                "
                @click="toggleAdmin(p)"
              />
            </div>
          </div>
        </template>
      </div>

      <ConversationBox
        v-else-if="activeConversationId"
        class="flex-grow min-h-0"
        :inbox-id="0"
        :is-contact-panel-open="false"
        :is-on-expanded-layout="false"
      />

      <div v-else class="flex items-center justify-center flex-grow p-6">
        <p class="text-sm text-center text-n-slate-11">
          {{ $t('GROUPS.NO_THREAD_YET') }}
        </p>
      </div>
    </aside>
  </div>
</template>
