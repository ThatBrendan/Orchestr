<script setup lang="ts">
import { useExecutionDialogFocus } from "@/composables/useExecutionDialogFocus";
import ProjectJoinAccess from "@/components/members/ProjectJoinAccess.vue";
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

import AppButton from "@/components/ui/AppButton.vue";
import AppConfirmDialog from "@/components/ui/AppConfirmDialog.vue";
import InviteMemberDialog from "@/components/members/InviteMemberDialog.vue";
import { presentLabel } from "@/lib/presentation";

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
 return row.remaining_minor === 0 ? "Settled" : (row.remaining_minor > 0 ? "Owes " : "Is owed ") + format(Math.abs(row.remaining_minor),row.currency);
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

const focusFallback = ref<HTMLElement | null>(null);
const restoreDialogFocus = useExecutionDialogFocus(computed(() => inviteOpen.value || !!confirmRemove.value), focusFallback);
</script>

<template>
  <div class="space-y-6 max-w-4xl fade-in">
    <h2
      ref="focusFallback"
      tabindex="-1"
      class="text-section-heading focus-ring"
    >
      People
    </h2>
    <div
      v-if="isPending"
      class="space-y-2"
      role="status"
      aria-label="Loading members"
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
      <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
        <p class="text-sm text-ink-soft">
          {{ roster.length }} {{ roster.length === 1 ? "person" : "people" }}
        </p>
        <AppButton
          v-if="canInvite"
          size="sm"
          variant="secondary"
          @click="inviteOpen = true"
        >
          Create invitation
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
        class="border rounded-xl divide-y divide-line border-line bg-surface"
      >
        <div
          v-for="m in roster"
          :key="m.member_id"
          class="px-4 py-3.5"
        >
          <div class="flex flex-wrap items-center gap-3.5">
            <AppAvatar
              :name="m.display_name"
              :url="m.avatar_url"
              :size="36"
            />
            <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
              <div class="text-card-heading font-semibold">
                {{ m.display_name }}
              </div>
              <div class="text-meta text-muted capitalize">
                {{ presentLabel(m.role) }}{{ m.status === 'invited' ? ' · Invited' : '' }}
              </div>
              <p
                v-if="budgetVisible && balanceLabel(m.member_id)"
                class="mt-1 text-meta text-muted"
              >
                {{ balanceLabel(m.member_id) }}
              </p>
            </div>
            <details
              v-if="canManage"
              class="w-full sm:w-auto"
            >
              <summary
                class="cursor-pointer min-h-11 rounded-lg px-3 py-3 text-sm text-ink-soft focus-ring"
                :aria-label="`Manage ${m.display_name}`"
              >
                Manage<span class="sr-only"> {{ m.display_name }}</span>
              </summary>
              <div class="mt-2 flex flex-wrap items-center gap-2">
                <select
                  v-if="canManage"
                  class="min-h-11 border rounded-lg px-3 py-2 text-sm focus-ring border-line bg-surface"
                  :disabled="updateRole.isPending.value || removeMember.isPending.value"
                  :value="m.role"
                  :aria-label="`Role for ${m.display_name}`"
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

                <AppButton
                  v-if="canManage"
                  variant="secondary"
                  size="sm"
                  :aria-label="`Remove ${m.display_name}`"
                  @click="confirmRemove = { id: m.member_id, name: m.display_name }"
                >
                  Remove
                </AppButton>
              </div>
            </details>
          </div>
          <p
            v-if="rowError[m.member_id]"
            role="alert"
            class="mt-2 text-meta text-danger"
          >
            {{ rowError[m.member_id] }}
          </p>
        </div>
      </div>
      <p
        v-if="budgetVisible && settlement.isError.value"
        role="status"
        class="mt-3 text-meta text-muted"
      >
        Balance information is unavailable. Membership controls are still available.
      </p>
      <ProjectJoinAccess
        v-if="allowed('project.invite')"
        :key="projectId"
        class="mt-6"
        :project-id="projectId"
        :read-only="archived"
      />
      <section
        v-if="allowed('project.invite')"
        class="mt-6 space-y-3"
      >
        <h2 class="text-section-heading">
          Invitations
        </h2>
        <p
          v-if="invitations.isPending.value"
          class="text-meta text-muted"
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
          class="text-meta text-muted"
        >
          No outstanding invitations.
        </p>
        <div
          v-for="inv in invitations.data.value"
          :key="inv.id"
          class="border border-line rounded-xl bg-surface p-4 text-sm [overflow-wrap:anywhere]"
        >
          <span>{{ inv.email }}</span>
          <p class="text-meta text-muted capitalize">
            {{ inv.status === 'pending' ? 'Pending invitation' : presentLabel(inv.status) }} · {{ presentLabel(inv.role) }}
          </p>
        </div>
      </section>
      <p
        v-if="removedCount > 0"
        class="mt-3 text-meta text-muted"
      >
        {{ removedCount }} former {{ removedCount === 1 ? "member has" : "members have" }} been removed.
      </p>
      <p
        v-if="archived"
        class="mt-3 text-meta text-warning"
      >
        This project is archived — membership is read-only.
      </p>
    </template>

    <InviteMemberDialog
      :open="inviteOpen"
      :project-id="projectId"
      @after-close="restoreDialogFocus"
      @close="inviteOpen = false"
    />
    <AppConfirmDialog
      :open="!!confirmRemove"
      title="Remove member"
      :message="`Remove ${confirmRemove?.name ?? ''} from this project? They'll lose access immediately.`"
      confirm-label="Remove"
      danger
      :loading="removeMember.isPending.value"
      @after-close="restoreDialogFocus"
      @close="confirmRemove = null"
      @confirm="confirmRemoveNow"
    />
  </div>
</template>
