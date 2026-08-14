<script setup>
import { ref, onMounted, computed } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AgentInvitesAPI from 'dashboard/api/agentInvites';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const getters = useStoreGetters();

const invites = ref([]);
const creating = ref(false);
const form = ref({ role: 'agent', teamId: '' });

const teams = computed(() => getters['teams/getTeams'].value || []);

const roleLabel = role =>
  role === 'administrator' ? 'Administrador' : 'Agente';

const fetchInvites = async () => {
  try {
    const { data } = await AgentInvitesAPI.get();
    invites.value = data;
  } catch (error) {
    // silent
  }
};

onMounted(() => {
  store.dispatch('teams/get');
  fetchInvites();
});

const createInvite = async () => {
  creating.value = true;
  try {
    const { data } = await AgentInvitesAPI.create({
      agent_invite: {
        role: form.value.role,
        team_id: form.value.teamId || null,
      },
    });
    invites.value.unshift(data);
    useAlert('Convite criado! Copie o link e envie ao colaborador.');
  } catch (error) {
    useAlert('Erro ao criar o convite.');
  } finally {
    creating.value = false;
  }
};

const revoke = async id => {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Revogar este convite? O link deixará de funcionar.')) {
    return;
  }
  try {
    await AgentInvitesAPI.delete(id);
    invites.value = invites.value.filter(invite => invite.id !== id);
  } catch (error) {
    useAlert('Erro ao revogar o convite.');
  }
};

const copyLink = async url => {
  try {
    await navigator.clipboard.writeText(url);
    useAlert('Link copiado!');
  } catch (error) {
    useAlert('Não foi possível copiar. Copie manualmente.');
  }
};

const fieldClass =
  'w-full px-3 py-2 text-sm rounded-lg outline-none border border-n-weak bg-n-background text-n-slate-12 focus:border-n-brand';
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="flex flex-col gap-6 p-8 w-[36rem] max-w-full">
    <div class="flex flex-col gap-1">
      <h2 class="text-lg font-semibold text-n-slate-12">Convite por link</h2>
      <p class="text-sm text-n-slate-11">
        Gere um link para o colaborador criar a própria conta (e-mail
        @welucci.com + senha). O time e a permissão já ficam definidos.
      </p>
    </div>

    <!-- Create -->
    <div class="flex items-end gap-3">
      <div class="flex flex-col gap-1.5 flex-1">
        <label class="text-sm font-medium text-n-slate-12">Permissão</label>
        <select v-model="form.role" :class="fieldClass">
          <option value="agent">Agente</option>
          <option value="administrator">Administrador</option>
        </select>
      </div>
      <div class="flex flex-col gap-1.5 flex-1">
        <label class="text-sm font-medium text-n-slate-12">
          Time (opcional)
        </label>
        <select v-model="form.teamId" :class="fieldClass">
          <option value="">Sem time</option>
          <option v-for="team in teams" :key="team.id" :value="team.id">
            {{ team.name }}
          </option>
        </select>
      </div>
      <Button
        label="Gerar link"
        icon="i-lucide-link"
        size="sm"
        :is-loading="creating"
        @click="createInvite"
      />
    </div>

    <!-- List -->
    <div v-if="invites.length" class="flex flex-col gap-2">
      <span class="text-xs font-medium tracking-wide uppercase text-n-slate-10">
        Convites ativos
      </span>
      <div
        v-for="invite in invites"
        :key="invite.id"
        class="flex items-center gap-3 p-3 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="flex flex-col min-w-0 gap-1">
          <div class="flex items-center gap-2">
            <span
              class="px-2 py-0.5 text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ roleLabel(invite.role) }}
            </span>
            <span v-if="invite.team_name" class="text-xs text-n-slate-11">
              · {{ invite.team_name }}
            </span>
          </div>
          <span class="text-xs truncate text-n-slate-10">
            {{ invite.invite_url }}
          </span>
        </div>
        <div class="flex items-center gap-1.5 ml-auto shrink-0">
          <Button
            label="Copiar"
            icon="i-lucide-copy"
            variant="outline"
            color="slate"
            size="sm"
            @click="copyLink(invite.invite_url)"
          />
          <Button
            icon="i-lucide-trash-2"
            variant="ghost"
            color="slate"
            size="sm"
            @click="revoke(invite.id)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
