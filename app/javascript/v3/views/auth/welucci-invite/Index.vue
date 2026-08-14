<script setup>
import { ref, onMounted, computed } from 'vue';
import axios from 'axios';

const props = defineProps({
  token: { type: String, required: true },
});

const loading = ref(true);
const submitting = ref(false);
const invalid = ref(false);
const done = ref(false);
const errorMsg = ref('');
const accountName = ref('');
const teamName = ref('');
const allowedDomain = ref('@welucci.com');

const form = ref({ name: '', email: '', password: '', confirmPassword: '' });

const emailValid = computed(() =>
  form.value.email.trim().toLowerCase().endsWith(allowedDomain.value)
);
const passwordsMatch = computed(
  () =>
    form.value.password.length > 0 &&
    form.value.password === form.value.confirmPassword
);
const canSubmit = computed(
  () =>
    form.value.name.trim() &&
    emailValid.value &&
    form.value.password.length >= 6 &&
    passwordsMatch.value
);

onMounted(async () => {
  try {
    const { data } = await axios.get(
      `/public/api/v1/agent_invites/${props.token}`
    );
    accountName.value = data.account_name;
    teamName.value = data.team_name;
    allowedDomain.value = data.allowed_domain || '@welucci.com';
  } catch (error) {
    invalid.value = true;
  } finally {
    loading.value = false;
  }
});

const submit = async () => {
  errorMsg.value = '';
  if (!canSubmit.value) return;
  submitting.value = true;
  try {
    await axios.post(`/public/api/v1/agent_invites/${props.token}/accept`, {
      name: form.value.name.trim(),
      email: form.value.email.trim().toLowerCase(),
      password: form.value.password,
    });
    done.value = true;
    setTimeout(() => {
      window.location.href = '/app/login';
    }, 2500);
  } catch (error) {
    errorMsg.value =
      error.response?.data?.error || 'Não foi possível concluir o cadastro.';
  } finally {
    submitting.value = false;
  }
};

const fieldClass =
  'w-full px-3 py-2 text-sm rounded-lg outline-none border border-n-weak bg-n-background text-n-slate-12 focus:border-n-brand';
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div
    class="flex items-center justify-center w-full min-h-screen p-4 bg-n-background"
  >
    <div
      class="w-full max-w-md p-8 border shadow-sm bg-n-solid-1 rounded-2xl border-n-weak"
    >
      <!-- Loading -->
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        Carregando convite...
      </div>

      <!-- Invalid -->
      <div v-else-if="invalid" class="py-6 text-center">
        <div
          class="flex items-center justify-center mx-auto mb-4 rounded-full size-14 bg-n-ruby-3 text-n-ruby-11"
        >
          <span class="i-lucide-triangle-alert size-7" />
        </div>
        <h1 class="text-lg font-semibold text-n-slate-12">Convite inválido</h1>
        <p class="mt-2 text-sm text-n-slate-11">
          Este convite não existe ou foi desativado. Peça um novo link ao seu
          administrador.
        </p>
      </div>

      <!-- Success -->
      <div v-else-if="done" class="py-6 text-center">
        <div
          class="flex items-center justify-center mx-auto mb-4 rounded-full size-14 bg-n-teal-3 text-n-teal-11"
        >
          <span class="i-lucide-check size-7" />
        </div>
        <h1 class="text-lg font-semibold text-n-slate-12">Conta criada!</h1>
        <p class="mt-2 text-sm text-n-slate-11">
          Redirecionando para o login...
        </p>
      </div>

      <!-- Form -->
      <form v-else class="flex flex-col gap-4" @submit.prevent="submit">
        <div class="text-center">
          <h1 class="text-xl font-semibold text-n-slate-12">
            Você foi convidado
          </h1>
          <p class="mt-1 text-sm text-n-slate-11">
            Crie seu acesso para
            <span class="font-medium text-n-slate-12">{{ accountName }}</span>
            <template v-if="teamName">
              · time
              <span class="font-medium text-n-slate-12">{{ teamName }}</span>
            </template>
          </p>
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">Nome</label>
          <input
            v-model="form.name"
            :class="fieldClass"
            placeholder="Seu nome"
          />
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">E-mail</label>
          <input
            v-model="form.email"
            type="email"
            :class="fieldClass"
            :placeholder="`voce${allowedDomain}`"
          />
          <span v-if="form.email && !emailValid" class="text-xs text-n-ruby-11">
            O e-mail precisa terminar com {{ allowedDomain }}
          </span>
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">Senha</label>
          <input
            v-model="form.password"
            type="password"
            :class="fieldClass"
            placeholder="Mínimo 6 caracteres"
          />
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            Confirmar senha
          </label>
          <input
            v-model="form.confirmPassword"
            type="password"
            :class="fieldClass"
            placeholder="Repita a senha"
          />
          <span
            v-if="form.confirmPassword && !passwordsMatch"
            class="text-xs text-n-ruby-11"
          >
            As senhas não coincidem
          </span>
        </div>

        <p v-if="errorMsg" class="text-sm text-center text-n-ruby-11">
          {{ errorMsg }}
        </p>

        <button
          type="submit"
          :disabled="!canSubmit || submitting"
          class="w-full py-2.5 text-sm font-medium text-white transition-colors rounded-lg bg-n-brand hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {{ submitting ? 'Criando...' : 'Criar minha conta' }}
        </button>
      </form>
    </div>
  </div>
</template>
