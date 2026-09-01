<script setup>
import { ref, computed, onMounted, nextTick, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';
import draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import { useTasksStore } from 'dashboard/stores/tasks';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TaskCard from '../components/TaskCard.vue';
import TaskDialog from '../components/TaskDialog.vue';
import TaskDetailDialog from '../components/TaskDetailDialog.vue';

const { t } = useI18n();
const tasksStore = useTasksStore();

// One clock for the board: the waiting badges age on their own, without a timer per card.
const now = ref(Date.now());
let clock = null;
onMounted(() => {
  clock = setInterval(() => {
    now.value = Date.now();
  }, 60000);
});
onUnmounted(() => clearInterval(clock));

const selectedBoardId = ref(null);
const taskDialogRef = ref(null);
const taskDetailDialogRef = ref(null);
const newBoardDialogRef = ref(null);
const columnNameInput = ref(null);

const dialogContext = ref({ task: null, defaultColumnId: null });
const detailContext = ref({ task: null, stageName: '' });
const newBoard = ref({ name: '', visibility: 'personal' });

const addingColumn = ref(false);
const newColumnName = ref('');
const editingColumnId = ref(null);
const editingColumnName = ref('');
const boardMenuOpen = ref(false);

const boards = computed(() => tasksStore.boardList);
const activeBoard = computed(() => tasksStore.activeBoard);
const uiFlags = computed(() => tasksStore.uiFlags);
const activeBoardName = computed(
  () =>
    activeBoard.value?.name ||
    boards.value.find(board => board.id === selectedBoardId.value)?.name ||
    ''
);

const selectBoard = async id => {
  if (!id) return;
  selectedBoardId.value = Number(id);
  await tasksStore.fetchBoard(id);
};

const selectBoardFromMenu = async id => {
  boardMenuOpen.value = false;
  await selectBoard(id);
};

onMounted(async () => {
  await tasksStore.fetchBoards();
  if (boards.value.length) await selectBoard(boards.value[0].id);
});

// Boards
const openNewBoard = () => {
  newBoard.value = { name: '', visibility: 'personal' };
  newBoardDialogRef.value.open();
};

const createBoard = async () => {
  if (!newBoard.value.name.trim()) return;
  try {
    const board = await tasksStore.createBoard({
      name: newBoard.value.name.trim(),
      visibility: newBoard.value.visibility,
    });
    newBoardDialogRef.value.close();
    await selectBoard(board.id);
  } catch (error) {
    useAlert(t('TASKS.ERROR'));
  }
};

const removeBoard = async () => {
  if (!activeBoard.value) return;
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('TASKS.DELETE_BOARD_CONFIRM'))) return;
  await tasksStore.deleteBoard(activeBoard.value.id);
  if (boards.value.length) await selectBoard(boards.value[0].id);
  else selectedBoardId.value = null;
};

// Columns
const submitNewColumn = async () => {
  if (!newColumnName.value.trim()) {
    addingColumn.value = false;
    return;
  }
  await tasksStore.createColumn(activeBoard.value.id, {
    name: newColumnName.value.trim(),
  });
  newColumnName.value = '';
  addingColumn.value = false;
};

const startEditColumn = async column => {
  editingColumnId.value = column.id;
  editingColumnName.value = column.name;
  await nextTick();
  columnNameInput.value?.[0]?.focus?.();
};

const saveColumnName = async column => {
  const name = editingColumnName.value.trim();
  editingColumnId.value = null;
  if (name && name !== column.name) {
    await tasksStore.updateColumn(activeBoard.value.id, column.id, { name });
  }
};

const removeColumn = async column => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('TASKS.DELETE_COLUMN_CONFIRM'))) return;
  await tasksStore.deleteColumn(activeBoard.value.id, column.id);
};

const onColumnDragChange = async event => {
  if (!event.moved) return;
  const updates = activeBoard.value.columns
    .map((column, index) =>
      column.position === index
        ? null
        : tasksStore.updateColumn(activeBoard.value.id, column.id, {
            position: index,
          })
    )
    .filter(Boolean);
  try {
    await Promise.all(updates);
  } catch (error) {
    useAlert(t('TASKS.ERROR'));
  }
};

// Tasks
const openNewTask = column => {
  dialogContext.value = { task: null, defaultColumnId: column.id };
  nextTick(() => taskDialogRef.value.open());
};

// Cards espelhados de um CRM abrem a visao de detalhe: o CRM e a fonte da verdade,
// entao nao faz sentido oferecer o formulario de edicao neles.
const openTask = (task, column) => {
  const attrs = task.customAttributes || {};
  if (attrs.pipedrive || attrs.hubspot) {
    detailContext.value = { task, stageName: column?.name || '' };
    nextTick(() => taskDetailDialogRef.value.open());
    return;
  }

  dialogContext.value = { task, defaultColumnId: task.taskColumnId };
  nextTick(() => taskDialogRef.value.open());
};

const removeTask = async task => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('TASKS.DELETE_TASK_CONFIRM'))) return;
  await tasksStore.deleteTask(task.id);
};

const onDragChange = async (event, column) => {
  const change = event.added || event.moved;
  if (!change) return;
  const task = change.element;
  task.taskColumnId = column.id;
  try {
    await tasksStore.persistMove({
      id: task.id,
      toColumnId: column.id,
      position: change.newIndex,
    });
  } catch (error) {
    useAlert(t('TASKS.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <!-- Header -->
    <header
      class="flex items-center justify-between gap-3 px-6 border-b h-14 border-n-weak shrink-0"
    >
      <div class="flex items-center gap-2.5 min-w-0">
        <h1 class="text-lg font-semibold text-n-slate-12 shrink-0">
          {{ t('TASKS.HEADER') }}
        </h1>
        <template v-if="boards.length">
          <span class="w-px h-5 bg-n-weak shrink-0" />
          <OnClickOutside @trigger="boardMenuOpen = false">
            <div class="relative shrink-0">
              <button
                class="flex items-center gap-1.5 py-1 pl-2 pr-1.5 rounded-md transition-colors hover:bg-n-alpha-1"
                @click="boardMenuOpen = !boardMenuOpen"
              >
                <span class="text-sm font-medium text-n-slate-12">
                  {{ activeBoardName }}
                </span>
                <span class="i-lucide-chevron-down size-4 text-n-slate-10" />
              </button>
              <div
                v-if="boardMenuOpen"
                class="absolute left-0 z-50 p-1 mt-1 border shadow-lg top-full min-w-56 rounded-xl border-n-weak bg-n-solid-1"
              >
                <button
                  v-for="board in boards"
                  :key="board.id"
                  class="flex items-center justify-between w-full gap-2 px-2.5 py-1.5 text-sm rounded-lg text-n-slate-12 hover:bg-n-alpha-1"
                  @click="selectBoardFromMenu(board.id)"
                >
                  <span class="truncate">{{ board.name }}</span>
                  <span
                    v-if="board.id === selectedBoardId"
                    class="i-lucide-check size-4 text-n-brand shrink-0"
                  />
                </button>
              </div>
            </div>
          </OnClickOutside>
          <span v-if="activeBoard" class="flex items-center gap-1.5 shrink-0">
            <span class="rounded-full size-1 bg-n-slate-8" />
            <span class="text-[11px] font-medium text-n-slate-10">
              {{
                activeBoard.visibility === 'shared'
                  ? t('TASKS.SHARED')
                  : t('TASKS.PERSONAL')
              }}
            </span>
          </span>
        </template>
      </div>
      <div class="flex items-center gap-1.5 shrink-0">
        <NextButton
          v-if="activeBoard"
          v-tooltip.bottom="t('TASKS.DELETE_BOARD')"
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-trash-2"
          @click="removeBoard"
        />
        <NextButton
          :label="t('TASKS.NEW_BOARD')"
          icon="i-lucide-plus"
          size="sm"
          @click="openNewBoard"
        />
      </div>
    </header>

    <!-- Empty state -->
    <div
      v-if="!boards.length && !uiFlags.fetchingBoards"
      class="flex flex-col items-center justify-center flex-1 gap-4"
    >
      <div
        class="flex items-center justify-center rounded-full size-14 bg-n-alpha-2 text-n-slate-10"
      >
        <span class="i-lucide-list-todo size-7" />
      </div>
      <p class="text-sm text-n-slate-11">{{ t('TASKS.EMPTY_BOARDS') }}</p>
      <NextButton
        :label="t('TASKS.CREATE_FIRST_BOARD')"
        icon="i-lucide-plus"
        @click="openNewBoard"
      />
    </div>

    <!-- Board -->
    <div
      v-else-if="activeBoard"
      class="flex items-start flex-1 gap-4 p-6 overflow-x-auto"
    >
      <draggable
        :list="activeBoard.columns"
        group="columns"
        item-key="id"
        handle=".column-drag"
        filter=".no-drag"
        :prevent-on-filter="false"
        :animation="150"
        :swap-threshold="0.6"
        class="flex items-start gap-4"
        ghost-class="opacity-40"
        @change="onColumnDragChange"
      >
        <template #item="{ element: column }">
          <section
            class="flex flex-col border w-80 shrink-0 max-h-full rounded-2xl bg-n-solid-1 border-n-weak"
          >
            <div
              class="flex items-center justify-between gap-2 px-3 py-3 group/column column-drag cursor-grab active:cursor-grabbing"
            >
              <div class="flex items-center gap-1.5 min-w-0">
                <span
                  class="transition-opacity opacity-0 shrink-0 i-lucide-grip-vertical size-4 text-n-slate-9 group-hover/column:opacity-100"
                />
                <input
                  v-if="editingColumnId === column.id"
                  ref="columnNameInput"
                  v-model="editingColumnName"
                  class="w-full px-1.5 py-1 text-sm font-medium border rounded-md outline-none no-drag bg-n-background border-n-brand text-n-slate-12"
                  @blur="saveColumnName(column)"
                  @keyup.enter="saveColumnName(column)"
                  @keyup.esc="editingColumnId = null"
                />
                <template v-else>
                  <h3
                    class="text-sm font-semibold truncate cursor-pointer text-n-slate-12"
                    @click="startEditColumn(column)"
                  >
                    {{ column.name }}
                  </h3>
                  <span
                    class="flex items-center justify-center h-5 px-1.5 min-w-5 text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
                  >
                    {{ column.tasks.length }}
                  </span>
                </template>
              </div>
              <div
                class="flex items-center gap-0.5 transition-opacity opacity-0 no-drag group-hover/column:opacity-100 shrink-0"
              >
                <button
                  v-tooltip.top="t('TASKS.RENAME_COLUMN')"
                  class="flex items-center justify-center rounded-md size-6 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  @click="startEditColumn(column)"
                >
                  <span class="i-lucide-pencil size-3.5" />
                </button>
                <button
                  v-tooltip.top="t('TASKS.DELETE_COLUMN')"
                  class="flex items-center justify-center rounded-md size-6 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-9"
                  @click="removeColumn(column)"
                >
                  <span class="i-lucide-trash-2 size-3.5" />
                </button>
              </div>
            </div>

            <draggable
              :list="column.tasks"
              group="tasks"
              item-key="id"
              :animation="150"
              class="flex flex-col flex-1 gap-2 px-2 overflow-y-auto min-h-[16px]"
              ghost-class="opacity-40"
              @change="onDragChange($event, column)"
            >
              <template #item="{ element }">
                <TaskCard
                  :task="element"
                  :now="now"
                  @click="openTask(element, column)"
                  @delete="removeTask(element)"
                />
              </template>
            </draggable>

            <p
              v-if="!column.tasks.length"
              class="px-3 py-6 text-xs text-center text-n-slate-10"
            >
              {{ t('TASKS.EMPTY_COLUMN') }}
            </p>

            <button
              class="flex items-center gap-2 px-2.5 py-2 m-2 text-sm transition-colors rounded-lg text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
              @click="openNewTask(column)"
            >
              <span class="i-lucide-plus size-4" />
              {{ t('TASKS.ADD_TASK') }}
            </button>
          </section>
        </template>
      </draggable>

      <!-- Add column -->
      <div class="w-80 shrink-0">
        <div
          v-if="addingColumn"
          class="p-2 border rounded-2xl bg-n-solid-1 border-n-weak"
        >
          <input
            v-model="newColumnName"
            class="w-full px-3 py-2 text-sm border rounded-lg outline-none border-n-weak bg-n-background text-n-slate-12 focus:border-n-brand"
            :placeholder="t('TASKS.COLUMN_NAME')"
            autofocus
            @keyup.enter="submitNewColumn"
            @keyup.esc="addingColumn = false"
          />
          <div class="flex items-center gap-2 mt-2">
            <NextButton
              :label="t('TASKS.SAVE')"
              size="sm"
              @click="submitNewColumn"
            />
            <NextButton
              :label="t('TASKS.CANCEL')"
              variant="ghost"
              color="slate"
              size="sm"
              @click="addingColumn = false"
            />
          </div>
        </div>
        <button
          v-else
          class="flex items-center justify-center w-full gap-2 py-3 text-sm transition-colors border border-dashed text-n-slate-11 rounded-2xl border-n-weak hover:border-n-slate-6 hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="addingColumn = true"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('TASKS.ADD_COLUMN') }}
        </button>
      </div>
    </div>

    <!-- Pipedrive card detail -->
    <TaskDetailDialog
      ref="taskDetailDialogRef"
      :task="detailContext.task"
      :stage-name="detailContext.stageName"
    />

    <!-- Task create/edit dialog -->
    <TaskDialog
      v-if="activeBoard"
      ref="taskDialogRef"
      :board="activeBoard"
      :task="dialogContext.task"
      :default-column-id="dialogContext.defaultColumnId"
    />

    <!-- New board dialog -->
    <Dialog
      ref="newBoardDialogRef"
      :title="t('TASKS.NEW_BOARD')"
      :confirm-button-label="t('TASKS.CREATE')"
      :disable-confirm-button="!newBoard.name.trim()"
      @confirm="createBoard"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('TASKS.BOARD_NAME') }}
          </label>
          <input
            v-model="newBoard.name"
            class="w-full px-3 py-2 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
            :placeholder="t('TASKS.BOARD_NAME_PLACEHOLDER')"
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('TASKS.VISIBILITY') }}
          </label>
          <select
            v-model="newBoard.visibility"
            class="w-full px-3 py-2 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
          >
            <option value="personal">{{ t('TASKS.PERSONAL') }}</option>
            <option value="shared">{{ t('TASKS.SHARED') }}</option>
          </select>
        </div>
      </div>
    </Dialog>
  </div>
</template>
