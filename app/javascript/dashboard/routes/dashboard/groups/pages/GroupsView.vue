<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import EvolutionGroupsAPI from 'dashboard/api/evolutionGroups';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

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
    return matchesName && matchesInstance;
  })
);

// Each instance is fetched on its own so the table fills in progressively and one slow
// number never blocks the rest.
const wait = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

// The server answers immediately with whatever is cached and schedules a background refresh,
// so an empty first answer means "come back shortly", not "no groups".
const loadInstance = async (name, refresh) => {
  let attempts = 0;
  let pending = true;
  while (pending && attempts < 20) {
    attempts += 1;
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
  }
  loadedCount.value += 1;
};

const loadGroups = async (refresh = false) => {
  isLoading.value = true;
  hasError.value = false;
  groups.value = [];
  loadedCount.value = 0;
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

const openGroup = async group => {
  selected.value = group;
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

onMounted(() => loadGroups());
</script>

<template>
  <div class="flex w-full h-full overflow-hidden">
    <div class="flex flex-col flex-grow h-full min-w-0 p-6 overflow-auto">
      <div class="flex flex-wrap items-start justify-between gap-3 mb-6">
        <div>
          <h1 class="text-lg font-medium text-n-slate-12">
            {{ $t('GROUPS.TITLE') }}
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
      <p v-else-if="hasError" class="text-sm text-n-ruby-11">
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
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="group in filtered"
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
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <aside
      v-if="selected"
      class="flex flex-col flex-shrink-0 h-full gap-4 p-6 overflow-auto border-l w-96 border-n-weak bg-n-solid-1"
    >
      <div class="flex items-start justify-between gap-2">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ $t('GROUPS.DETAIL.TITLE') }}
        </h2>
        <NextButton
          xs
          ghost
          slate
          icon="i-lucide-x"
          :aria-label="$t('GROUPS.DETAIL.CLOSE')"
          @click="selected = null"
        />
      </div>

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
        :label="$t('GROUPS.DETAIL.SAVE')"
        class="w-fit"
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
            <span class="text-sm text-n-slate-11">
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
    </aside>
  </div>
</template>
