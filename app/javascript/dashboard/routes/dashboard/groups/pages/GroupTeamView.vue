<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import GroupTeamAPI from 'dashboard/api/groupTeam';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const team = ref([]);
const isLoading = ref(false);
const phoneNumber = ref('');
const name = ref('');

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await GroupTeamAPI.get();
    team.value = data.team || [];
  } finally {
    isLoading.value = false;
  }
};

const add = async () => {
  if (!phoneNumber.value.trim()) return;
  await GroupTeamAPI.add(phoneNumber.value.trim(), name.value.trim());
  phoneNumber.value = '';
  name.value = '';
  await load();
};

const remove = async member => {
  await GroupTeamAPI.remove(member.id);
  await load();
};

const syncFromInstances = async () => {
  isLoading.value = true;
  try {
    await GroupTeamAPI.syncFromInstances();
    await load();
    useAlert(t('GROUPS.TEAM.SYNCED'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full p-6 overflow-auto">
    <div class="flex flex-wrap items-start justify-between gap-3 mb-6">
      <div>
        <h1 class="text-lg font-medium text-n-slate-12">
          {{ $t('GROUPS.TEAM.TITLE') }}
        </h1>
        <p class="mt-1 max-w-prose text-sm text-n-slate-11">
          {{ $t('GROUPS.TEAM.SUBTITLE') }}
        </p>
      </div>
      <NextButton
        sm
        faded
        slate
        icon="i-lucide-refresh-cw"
        :is-loading="isLoading"
        :label="$t('GROUPS.TEAM.SYNC')"
        @click="syncFromInstances"
      />
    </div>

    <form class="flex flex-wrap items-end gap-3 mb-6" @submit.prevent="add">
      <label class="mb-0">
        {{ $t('GROUPS.TEAM.PHONE') }}
        <input
          v-model="phoneNumber"
          type="text"
          class="w-56 mb-0"
          :placeholder="$t('GROUPS.TEAM.PHONE_PLACEHOLDER')"
        />
      </label>
      <label class="mb-0">
        {{ $t('GROUPS.TEAM.NAME') }}
        <input v-model="name" type="text" class="w-56 mb-0" />
      </label>
      <NextButton sm type="submit" :label="$t('GROUPS.TEAM.ADD')" />
    </form>

    <div class="overflow-x-auto border rounded-lg border-n-weak">
      <table class="w-full text-sm">
        <thead class="bg-n-slate-2">
          <tr class="text-left text-n-slate-11">
            <th class="px-4 py-2 font-medium">{{ $t('GROUPS.TEAM.NAME') }}</th>
            <th class="px-4 py-2 font-medium">{{ $t('GROUPS.TEAM.PHONE') }}</th>
            <th class="px-4 py-2 font-medium">
              {{ $t('GROUPS.TEAM.SOURCE') }}
            </th>
            <th class="px-4 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="member in team"
            :key="member.id"
            class="border-t border-n-weak"
          >
            <td class="px-4 py-2 text-n-slate-12">{{ member.name }}</td>
            <td class="px-4 py-2 tabular-nums text-n-slate-11">
              {{ member.phone_number }}
            </td>
            <td class="px-4 py-2 text-n-slate-11">
              {{
                member.source === 'instance'
                  ? $t('GROUPS.TEAM.FROM_INSTANCE')
                  : $t('GROUPS.TEAM.MANUAL')
              }}
            </td>
            <td class="px-4 py-2 text-right">
              <NextButton
                xs
                ghost
                ruby
                :label="$t('GROUPS.TEAM.REMOVE')"
                @click="remove(member)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
