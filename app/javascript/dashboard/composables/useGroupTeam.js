import { ref, computed } from 'vue';
import GroupTeamAPI from 'dashboard/api/groupTeam';

// The roster is small and rarely changes, so it is fetched once per session and shared by
// every message bubble instead of being re-requested per conversation.
const members = ref([]);
const isLoaded = ref(false);
let inFlight = null;

const phoneSet = computed(
  () => new Set(members.value.map(m => m.phone_number))
);

const loadTeam = async () => {
  if (isLoaded.value) return;
  if (!inFlight) {
    inFlight = GroupTeamAPI.get()
      .then(({ data }) => {
        members.value = data.team || [];
        isLoaded.value = true;
      })
      .catch(() => {
        // A missing roster only means nobody is highlighted yet.
        isLoaded.value = true;
      })
      .finally(() => {
        inFlight = null;
      });
  }
  await inFlight;
};

export function useGroupTeam() {
  const isTeamMember = phone => Boolean(phone) && phoneSet.value.has(phone);

  const addToTeam = async (phone, name) => {
    const { data } = await GroupTeamAPI.add(phone, name);
    members.value = [...members.value, data.member];
  };

  return { members, isLoaded, loadTeam, isTeamMember, addToTeam };
}
