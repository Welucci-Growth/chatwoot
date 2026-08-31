<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useStore } from 'vuex';
import EvolutionGroupsAPI from 'dashboard/api/evolutionGroups';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useGroupTeam } from 'dashboard/composables/useGroupTeam';

const props = defineProps({
  filter: {
    type: String,
    default: 'all',
  },
});

const { t } = useI18n();
const store = useStore();

const groups = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const loadedCount = ref(0);
const totalInstances = ref(0);
const search = ref('');
const instanceFilter = ref('');

const selected = ref(null);
const details = ref(null);
const isLoadingDetails = ref(false);
const showSettings = ref(false);
const draftSubject = ref('');
const draftDescription = ref('');

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
    return matchesName && matchesInstance && matchesFilter;
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

const waitingLabel = group => {
  if (!group.waiting_since) return '';
  const minutes = Math.floor(
    (Date.now() - new Date(group.waiting_since)) / 60000
  );
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
const wait = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

// The server answers immediately with whatever is cached and schedules a background refresh,
// so an empty first answer means "come back shortly", not "no groups".
const failedInstances = ref([]);

const loadInstance = async (name, refresh) => {
  let attempts = 0;
  let pending = true;
  while (pending && attempts < 20) {
    attempts += 1;
    try {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await EvolutionGroupsAPI.getGroupsForInstance(
        name,
        refresh && attempts === 1
      );
      pending = data.pending;
      if (!pending) {
        groups.value = [...groups.value, ...(data.groups || [])];
      } else {
        // eslint-disable-next-line no-await-in-loop
        await wait(5000);
      }
    } catch (error) {
      // One unreachable number must not cost us the other six.
      failedInstances.value = [...failedInstances.value, name];
      pending = false;
    }
  }
  loadedCount.value += 1;
};

const loadGroups = async (refresh = false) => {
  isLoading.value = true;
  hasError.value = false;
  groups.value = [];
  loadedCount.value = 0;
  failedInstances.value = [];
  try {
    const { data } = await EvolutionGroupsAPI.getInstances();
    instanceNames.value = (data.instances || []).map(i => i.name);
    totalInstances.value = instanceNames.value.length;

    // Sequential on purpose: hitting every instance at once would pile requests onto the
    // Evolution server, which already needs up to 40 seconds per call.
    await instanceNames.value.reduce(
      (chain, name) => chain.then(() => loadInstance(name, refresh)),
      Promise.resolve()
    );
  } catch (error) {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const activeConversationId = ref(null);

// Groups that have already spoken have a real Chatwoot conversation, so the thread is the
// standard conversation pane rather than a second, parallel chat implementation.
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
        </div>
        <NextButton
          sm
          faded
          slate
          icon="i-lucide-refresh-cw"
          :is-loading="isLoading"
          :label="$t('GROUPS.REFRESH')"
          @click="loadGroups(true)"
        />
      </div>

      <div class="flex flex-wrap gap-3 mb-4">
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
        {{
          $t('GROUPS.LOADING_PROGRESS', {
            done: loadedCount,
            total: totalInstances,
          })
        }}
      </p>
      <p v-if="hasError" class="mb-3 text-sm text-n-ruby-11">
        {{ $t('GROUPS.ERROR') }}
      </p>
      <p
        v-else-if="failedInstances.length"
        class="mb-3 text-sm text-n-amber-11"
      >
        {{
          $t('GROUPS.PARTIAL_ERROR', { numbers: failedInstances.join(', ') })
        }}
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
                  class="px-2 py-0.5 text-xs rounded-full bg-n-amber-3 text-n-amber-11 whitespace-nowrap"
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
