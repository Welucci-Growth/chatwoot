<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useTasksStore } from 'dashboard/stores/tasks';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  board: { type: Object, required: true },
  boards: { type: Array, default: () => [] },
  task: { type: Object, default: null },
  defaultColumnId: { type: [Number, String], default: null },
  prefill: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();
const store = useStore();
const tasksStore = useTasksStore();

const dialogRef = ref(null);
const isSaving = ref(false);
const currentBoard = ref(props.board);

const form = ref({
  title: '',
  description: '',
  taskColumnId: null,
  assigneeId: null,
  dueOn: '',
  labels: '',
});
const contactId = ref(null);
const contactName = ref('');
const conversationId = ref(null);

const columns = computed(() => currentBoard.value?.columns || []);
const agents = computed(() => store.getters['agents/getAgents'] || []);
const isEditing = computed(() => Boolean(props.task));
const showBoardSelect = computed(
  () => !isEditing.value && props.boards.length > 1
);

const toDateInput = epoch => {
  const date = new Date(epoch * 1000);
  const pad = value => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
};

const resetForm = () => {
  if (props.task) {
    form.value = {
      title: props.task.title || '',
      description: props.task.description || '',
      taskColumnId: props.task.taskColumnId,
      assigneeId: props.task.assignee?.id || null,
      dueOn: props.task.dueOn ? toDateInput(props.task.dueOn) : '',
      labels: (props.task.labels || []).join(', '),
    };
    contactId.value = props.task.contact?.id || null;
    contactName.value = props.task.contact?.name || '';
    conversationId.value = props.task.conversationId || null;
  } else {
    form.value = {
      title: props.prefill?.title || '',
      description: '',
      taskColumnId: props.defaultColumnId || columns.value[0]?.id || null,
      assigneeId: null,
      dueOn: '',
      labels: '',
    };
    contactId.value = props.prefill?.contactId || null;
    contactName.value = props.prefill?.contactName || '';
    conversationId.value = props.prefill?.conversationId || null;
  }
};

const open = () => {
  currentBoard.value = props.board;
  resetForm();
  dialogRef.value.open();
};
defineExpose({ open });

const onBoardChange = async event => {
  const id = Number(event.target.value);
  if (id === currentBoard.value?.id) return;
  try {
    currentBoard.value = await tasksStore.getBoardDetail(id);
    form.value.taskColumnId = columns.value[0]?.id || null;
  } catch (error) {
    useAlert(t('TASKS.ERROR'));
  }
};

const buildPayload = () => ({
  title: form.value.title.trim(),
  description: form.value.description,
  task_board_id: currentBoard.value.id,
  task_column_id: form.value.taskColumnId,
  assignee_id: form.value.assigneeId || null,
  contact_id: contactId.value || null,
  conversation_id: conversationId.value || null,
  due_on: form.value.dueOn || null,
  label_list: form.value.labels
    .split(',')
    .map(label => label.trim())
    .filter(Boolean),
});

const onConfirm = async () => {
  if (!form.value.title.trim()) return;
  isSaving.value = true;
  try {
    if (isEditing.value) {
      await tasksStore.updateTask(props.task.id, buildPayload());
      useAlert(t('TASKS.UPDATED'));
    } else {
      await tasksStore.createTask(buildPayload());
      useAlert(t('TASKS.CREATED'));
    }
    emit('saved');
    dialogRef.value.close();
  } catch (error) {
    useAlert(t('TASKS.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

store.dispatch('agents/get');

const fieldClass =
  'w-full px-3 py-2 text-sm rounded-lg outline-none border border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand';
const labelClass = 'text-sm font-medium text-n-slate-12';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="isEditing ? t('TASKS.EDIT_TASK') : t('TASKS.NEW_TASK')"
    :confirm-button-label="isEditing ? t('TASKS.SAVE') : t('TASKS.CREATE')"
    :is-loading="isSaving"
    :disable-confirm-button="!form.title.trim()"
    @confirm="onConfirm"
  >
    <div class="flex flex-col gap-4">
      <div v-if="showBoardSelect" class="flex flex-col gap-1.5">
        <label :class="labelClass">{{ t('TASKS.FORM.BOARD') }}</label>
        <select
          :value="currentBoard?.id"
          :class="fieldClass"
          @change="onBoardChange"
        >
          <option
            v-for="boardOption in boards"
            :key="boardOption.id"
            :value="boardOption.id"
          >
            {{ boardOption.name }}
          </option>
        </select>
      </div>

      <div class="flex flex-col gap-1.5">
        <label :class="labelClass">{{ t('TASKS.FORM.TITLE') }}</label>
        <input
          v-model="form.title"
          :class="fieldClass"
          :placeholder="t('TASKS.FORM.TITLE_PLACEHOLDER')"
        />
      </div>

      <div class="flex flex-col gap-1.5">
        <label :class="labelClass">{{ t('TASKS.FORM.DESCRIPTION') }}</label>
        <textarea
          v-model="form.description"
          rows="3"
          :class="fieldClass"
          :placeholder="t('TASKS.FORM.DESCRIPTION_PLACEHOLDER')"
        />
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1.5">
          <label :class="labelClass">{{ t('TASKS.FORM.COLUMN') }}</label>
          <select v-model="form.taskColumnId" :class="fieldClass">
            <option
              v-for="column in columns"
              :key="column.id"
              :value="column.id"
            >
              {{ column.name }}
            </option>
          </select>
        </div>

        <div class="flex flex-col gap-1.5">
          <label :class="labelClass">{{ t('TASKS.FORM.ASSIGNEE') }}</label>
          <select v-model="form.assigneeId" :class="fieldClass">
            <option :value="null">{{ t('TASKS.FORM.UNASSIGNED') }}</option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1.5">
          <label :class="labelClass">{{ t('TASKS.FORM.DUE_ON') }}</label>
          <input v-model="form.dueOn" type="date" :class="fieldClass" />
        </div>
        <div class="flex flex-col gap-1.5">
          <label :class="labelClass">{{ t('TASKS.FORM.CONTACT') }}</label>
          <input
            :value="contactName || t('TASKS.FORM.NO_CONTACT')"
            :class="fieldClass"
            disabled
          />
        </div>
      </div>

      <div class="flex flex-col gap-1.5">
        <label :class="labelClass">{{ t('TASKS.FORM.LABELS') }}</label>
        <input
          v-model="form.labels"
          :class="fieldClass"
          :placeholder="t('TASKS.FORM.LABELS_PLACEHOLDER')"
        />
      </div>
    </div>
  </Dialog>
</template>
