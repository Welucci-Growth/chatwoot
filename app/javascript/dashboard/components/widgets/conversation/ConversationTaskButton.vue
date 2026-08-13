<script setup>
import { ref, computed, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useTasksStore } from 'dashboard/stores/tasks';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TaskDialog from 'dashboard/routes/dashboard/tasks/components/TaskDialog.vue';

const { t } = useI18n();
const store = useStore();
const tasksStore = useTasksStore();

const dialogRef = ref(null);
const dialogBoard = ref(null);
const dialogBoards = ref([]);
const prefill = ref({});
const isPreparing = ref(false);

const currentChat = computed(() => store.getters.getSelectedChat);

const openTaskDialog = async () => {
  const chat = currentChat.value;
  if (!chat?.id) return;

  isPreparing.value = true;
  try {
    await tasksStore.fetchBoards();
    let board =
      tasksStore.boardList.find(item => item.visibility === 'personal') ||
      tasksStore.boardList[0];
    if (!board) {
      board = await tasksStore.createBoard({
        name: 'Minhas tarefas',
        visibility: 'personal',
      });
    }
    const detail = board.columns
      ? board
      : await tasksStore.getBoardDetail(board.id);

    const sender = chat.meta?.sender || {};
    dialogBoard.value = detail;
    dialogBoards.value = tasksStore.boardList;
    prefill.value = {
      title: sender.name || '',
      contactId: sender.id || null,
      contactName: sender.name || '',
      conversationId: chat.id,
    };

    await nextTick();
    dialogRef.value.open();
  } catch (error) {
    useAlert(t('TASKS.ERROR'));
  } finally {
    isPreparing.value = false;
  }
};
</script>

<template>
  <span class="inline-flex">
    <NextButton
      v-tooltip.top-end="t('TASKS.CONVERSATION_BUTTON')"
      icon="i-lucide-list-todo"
      slate
      faded
      sm
      :is-loading="isPreparing"
      @click="openTaskDialog"
    />
    <TaskDialog
      v-if="dialogBoard"
      ref="dialogRef"
      :board="dialogBoard"
      :boards="dialogBoards"
      :prefill="prefill"
    />
  </span>
</template>
