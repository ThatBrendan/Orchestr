<script setup lang="ts">
import { useProjectSettlement } from "@/composables/useSettlement";
import { useMoney } from "@/composables/useMoney";
import { isProjectModuleVisible } from "@/lib/projectProfiles";
import { computed, ref } from "vue";
import { useProjectInvitations } from "@/composables/useNotifications";
import { useRoute } from "vue-router";
import { useMemberDirectory } from "@/composables/useProject";
import { useUpdateMemberRole, useRemoveMember } from "@/composables/useMembers";
import { useProjectContext } from "@/composables/useProjectContext";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import type { MemberRole } from "@/types/database";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import AppAvatar from "@/components/ui/AppAvatar.vue";
import StatusBadge from "@/components/ui/StatusBadge.vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import InviteMemberDialog from "@/components/members/InviteMemberDialog.vue";
import { getSettlementPresentation, presentLabel } from "@/lib/presentation";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { members, isPending, isError, error, refetch } = useMemberDirectory(projectId);
const { allowed, project } = useProjectContext();
const toast = useToast();
const { format } = useMoney();
const budgetVisible = computed(() => isProjectModuleVisible(project.value?.profile,project.value?.module_visibility,"budget"));
const settlement = useProjectSettlement(projectId,budgetVisible);
function balanceLabel(id: string) {
 const row=settlement.data.value?.members.find(m=>m.member_id===id);
 if(!row) return "";
 const presentation = getSettlementPresentation(row.paid_minor, row.remaining_minor);
 return row.remaining_minor === 0 ? presentation.label : `${presentation.label} · ${format(Math.abs(row.remaining_minor),row.currency)} ${row.remaining_minor<0 ? 'credit' : 'remaining'}`;
}

function balanceTone(id: string) {
 const row=settlement.data.value?.members.find(m=>m.member_id===id);
 return row ? getSettlementPresentation(row.paid_minor, row.remaining_minor).tone : "accent";
}

const roster = computed(() => members.value.filter((m) => m.status !== "removed"));
const removedCount = computed(() => members.value.length - roster.value.length);
const archived = computed(() => project.value?.status === "archived");
const canManage = computed(() => allowed("members.manage") && !archived.value);
const canInvite = computed(() => allowed("project.invite") && !archived.value);

const invitations = useProjectInvitations(projectId, () => allowed("project.invite"));

const updateRole = useUpdateMemberRole(projectId.value);
const removeMember = useRemoveMember(projectId.value);

const rowError = ref<Record<string, string>>({});
const inviteOpen = ref(false);
const confirmRemove = ref<{ id: string; name: string } | null>(null);

async function onRoleChange(memberId: string, event: Event) {
  const control = event.target as HTMLSelectElement;
  const role = control.value as MemberRole;
  rowError.value = { ...rowError.value, [memberId]: "" };
  try {
    await updateRole.mutateAsync({ memberId, role });
    toast.success("Role updated.");
  } catch (e) {
    rowError.value = { ...rowError.value, [memberId]: toAppError(e).message };
  } finally {
    control.value = members.value.find((m) => m.member_id === memberId)?.role ?? "viewer";
  }
}

async function confirmRemoveNow() {
  if (!confirmRemove.value) return;
  const { id } = confirmRemove.value;
  try {
    await removeMember.mutateAsync(id);
    toast.success("Member removed.");
    confirmRemove.value = null;
  } catch (e) {
    rowError.value = { ...rowError.value, [id]: toAppError(e).message };
    confirmRemove.value = null;
  }
}

const roleTone = (r: string) => (r === "organizer" ? "accent" : "neutral");
const statusTone = (s: string) => (s === "invited" ? "amber" : s === "removed" ? "neutral" : "accent");
</script>

<template>
  <div class="fade-in">
    <div
      v-if="isPending"
      class="space-y-2"
    >
      <SkeletonBlock
        v-for="i in 4"
        :key="i"
        height="56px"
        rounded="0.5rem"
      />
    </div>
    <ErrorState
      v-else-if="isError"
      :error="error"
      :retry="() => refetch()"
    />
    <template v-else>
      <div class="flex items-center justify-between mb-4">
        <p class="text-14 text-ink-soft">
          {{ roster.length }} {{ roster.length === 1 ? "person" : "people" }}
        </p>
        <AppButton
          v-if="canInvite"
          size="sm"
          @click="inviteOpen = true"
        >
          Invite
        </AppButton>
      </div>

      <EmptyState
        v-if="roster.length === 0"
        message="No one has been added to this project yet."
      >
        <template
          v-if="canInvite"
          #action
        >
          <AppButton
            size="sm"
            @click="inviteOpen = true"
          >
            Invite someone
          </AppButton>
        </template>
      </EmptyState>

      <div
        v-else
        class="border rounded-xl divide-y border-line bg-surface"
      >
        <div
          v-for="m in roster"
          :key="m.member_id"
          class="px-4 py-3.5"
        >
          <div class="flex items-center gap-3.5">
            <AppAvatar
              :name="m.display_name"
              :url="m.avatar_url"
              :size="36"
            />
            <div class="min-w-0 flex-1">
              <div class="text-14 font-medium">
                {{ m.display_name }}
                <span
                  v-if="budgetVisible && balanceLabel(m.member_id)"
                  class="block text-13 font-normal"
                  :class="{
                    'text-danger': balanceTone(m.member_id) === 'danger',
                    'text-amber': balanceTone(m.member_id) === 'amber',
                    'text-accent': balanceTone(m.member_id) === 'accent',
                  }"
                >{{ balanceLabel(m.member_id) }}</span>
              </div>
              <div class="text-13 text-muted capitalize">
                {{ presentLabel(m.role) }}
              </div>
            </div>
            <StatusBadge
              v-if="m.status === 'invited'"
              label="Invited"
              :tone="statusTone(m.status)"
            />

            <select
              v-if="canManage"
              class="border rounded-lg px-2 py-1.5 text-13 focus-ring border-line bg-surface"
              :disabled="updateRole.isPending.value || removeMember.isPending.value"
              :value="m.role"
              @change="onRoleChange(m.member_id, $event)"
            >
              <option value="organizer">
                Organizer
              </option>
              <option value="member">
                Member
              </option>
              <option value="viewer">
                Viewer
              </option>
            </select>
            <StatusBadge
              v-else-if="m.role === 'organizer'"
              label="Organizer"
              :tone="roleTone(m.role)"
            />

            <AppButton
              v-if="canManage"
              variant="secondary"
              size="sm"
              @click="confirmRemove = { id: m.member_id, name: m.display_name }"
            >
              Remove
            </AppButton>
          </div>
          <p
            v-if="rowError[m.member_id]"
            class="mt-2 text-13 text-danger"
          >
            {{ rowError[m.member_id] }}
          </p>
        </div>
      </div>
      <section
        v-if="allowed('project.invite')"
        class="mt-6 space-y-3"
      >
        <h2 class="font-medium text-14">
          Invitations
        </h2>
        <p
          v-if="invitations.isPending.value"
          class="text-13 text-muted"
        >
          Loading invitations…
        </p>
        <ErrorState
          v-else-if="invitations.isError.value"
          :error="invitations.error.value"
          :retry="() => invitations.refetch()"
        />
        <p
          v-else-if="!invitations.data.value?.length"
          class="text-13 text-muted"
        >
          No outstanding invitations.
        </p>
        <div
          v-for="inv in invitations.data.value"
          :key="inv.id"
          class="border border-line rounded-lg p-3 text-14"
        >
          <span>{{ inv.email }}</span>
          <p class="text-13 text-muted capitalize">
            {{ inv.status === 'pending' ? 'Pending invitation' : presentLabel(inv.status) }} · {{ presentLabel(inv.role) }}
          </p>
        </div>
      </section>
      <p
        v-if="removedCount > 0"
        class="mt-3 text-13 text-muted"
      >
        {{ removedCount }} former {{ removedCount === 1 ? "member has" : "members have" }} been removed.
      </p>
      <p
        v-if="archived"
        class="mt-3 text-13 text-amber"
      >
        This project is archived — membership is read-only.
      </p>
    </template>

    <InviteMemberDialog
      :open="inviteOpen"
      :project-id="projectId"
      @close="inviteOpen = false"
    />
    <AppConfirmDialog
      :open="!!confirmRemove"
      title="Remove member"
      :message="`Remove ${confirmRemove?.name ?? ''} from this project? They'll lose access immediately.`"
      confirm-label="Remove"
      danger
      :loading="removeMember.isPending.value"
      @close="confirmRemove = null"
      @confirm="confirmRemoveNow"
    />
  </div>
</template>
