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
const { allowed, project, context } = useProjectContext();
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

const joinAccess = ref<InstanceType<typeof ProjectJoinAccess> | null>(null);
const joinBusy = ref(false);
const joinState = ref({ loading: false, pendingCount: 0, error: "" });

function copyInviteLink() {
  void joinAccess.value?.copy();
}

function onJoinAccessChange(value: { loading: boolean; pendingCount: number; error: string }) {
  joinState.value = value;
}
</script>

<template>
  <div class="space-y-8 max-w-4xl fade-in">
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <h2
          ref="focusFallback"
          tabindex="-1"
          class="text-section-heading focus-ring"
        >
          People
        </h2>
      </div>
      <div
        v-if="allowed('project.invite')"
        class="flex flex-wrap gap-2"
      >
        <AppButton
          size="sm"
          variant="secondary"
          :loading="joinBusy"
          :disabled="joinBusy || archived"
          @click="copyInviteLink"
        >
          Copy invite link
        </AppButton>
        <AppButton
          v-if="canInvite"
          size="sm"
          variant="secondary"
          @click="inviteOpen = true"
        >
          Create invitation
        </AppButton>
      </div>
    </header>
    <p
      v-if="archived"
      class="text-meta text-warning"
    >
      This project is archived — membership is read-only.
    </p>

    <section
      aria-labelledby="people-members-heading"
      class="space-y-4"
    >
      <div class="flex items-baseline justify-between gap-3">
        <h3
          id="people-members-heading"
          class="text-section-heading"
        >
          Members
        </h3>
        <p
          v-if="!isPending && !isError"
          class="text-meta text-muted"
        >
          {{ roster.length }} {{ roster.length === 1 ? 'person' : 'people' }}
        </p>
      </div>
      <div
        v-if="isPending"
        class="grid gap-3 xl:grid-cols-2"
        role="status"
        aria-label="Loading members"
      >
        <div
          v-for="i in 4"
          :key="i"
          class="flex gap-4 rounded-xl border border-line p-4"
        >
          <SkeletonBlock
            width="48px"
            height="48px"
            rounded="50%"
          />
          <div class="flex-1 space-y-3">
            <SkeletonBlock
              width="75%"
              height="20px"
            /><SkeletonBlock
              width="45%"
              height="16px"
            />
          </div>
        </div>
      </div>
      <ErrorState
        v-else-if="isError"
        :error="error"
        :retry="() => refetch()"
      />
      <EmptyState
        v-else-if="roster.length === 0"
        message="No one has been added to this project yet."
      />
      <div
        v-else
        class="grid gap-3 xl:grid-cols-2"
      >
        <article
          v-for="m in roster"
          :key="m.member_id"
          class="min-w-0 rounded-xl border border-line bg-surface p-4"
          :aria-label="m.display_name"
        >
          <div class="flex items-start gap-3.5">
            <span
              aria-hidden="true"
              class="rounded-full"
              :class="m.role === 'organizer' ? 'ring-2 ring-brand/20 ring-offset-2' : ''"
            >
              <AppAvatar
                :name="m.display_name"
                :url="m.avatar_url"
                :size="48"
                :tone="m.role === 'organizer' ? 'ink' : 'muted'"
              />
            </span>
            <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
              <h4 class="text-card-heading font-semibold">
                {{ m.display_name }} <span
                  v-if="m.member_id === context?.memberId"
                  class="text-meta font-normal text-muted"
                >· You</span>
              </h4>
              <p
                class="mt-1 text-meta"
                :class="m.role === 'organizer' ? 'text-brand' : 'text-muted'"
              >
                {{ presentLabel(m.role) }}{{ m.status === 'invited' ? ' · Invited' : '' }}
              </p>
              <p
                v-if="budgetVisible && balanceLabel(m.member_id)"
                class="mt-2 text-meta text-muted"
              >
                {{ balanceLabel(m.member_id) }}
              </p>
            </div>
          </div>
          <details
            v-if="canManage"
            class="mt-3 border-t border-line pt-1"
          >
            <summary
              class="cursor-pointer min-h-11 rounded-lg px-2 py-3 text-meta text-ink-soft focus-ring"
              :aria-label="`Manage ${m.display_name}`"
            >
              Manage<span class="sr-only"> {{ m.display_name }}</span>
            </summary>
            <div class="mt-1 flex flex-wrap items-center gap-2">
              <select
                class="min-h-11 border rounded-lg px-3 py-2 text-sm focus-ring border-line bg-surface"
                :disabled="updateRole.isPending.value || removeMember.isPending.value"
                :value="m.role"
                :aria-label="`Role for ${m.display_name}`"
                @change="onRoleChange(m.member_id, $event)"
              >
                <option value="organizer">
                  Organizer
                </option><option value="member">
                  Member
                </option><option value="viewer">
                  Viewer
                </option>
              </select>
              <AppButton
                variant="secondary"
                size="sm"
                :aria-label="`Remove ${m.display_name}`"
                @click="confirmRemove = { id: m.member_id, name: m.display_name }"
              >
                Remove
              </AppButton>
            </div>
          </details>
          <p
            v-if="rowError[m.member_id]"
            role="alert"
            class="mt-2 text-meta text-danger"
          >
            {{ rowError[m.member_id] }}
          </p>
        </article>
      </div>
      <p
        v-if="budgetVisible && settlement.isError.value"
        role="status"
        class="text-meta text-muted"
      >
        Balance information is unavailable. Membership controls are still available.
      </p>
      <p
        v-if="!isError && removedCount > 0"
        class="text-meta text-muted"
      >
        {{ removedCount }} former {{ removedCount === 1 ? 'member has' : 'members have' }} been removed.
      </p>
    </section>

    <section
      v-if="allowed('project.invite')"
      aria-labelledby="people-invitations-heading"
      class="space-y-4"
    >
      <h3
        id="people-invitations-heading"
        class="text-section-heading"
      >
        Invitations
      </h3>
      <ProjectJoinAccess
        v-if="allowed('project.invite')"
        ref="joinAccess"
        :key="projectId"
        :project-id="projectId"
        :read-only="archived"
        @busy-change="joinBusy = $event"
        @access-change="onJoinAccessChange"
      />
      <div
        v-if="invitations.isPending.value"
        role="status"
        aria-label="Loading invitations"
        class="space-y-3"
      >
        <SkeletonBlock
          v-for="i in 2"
          :key="i"
          height="88px"
          rounded="0.75rem"
        />
      </div>
      <ErrorState
        v-else-if="invitations.isError.value"
        :error="invitations.error.value"
        :retry="() => invitations.refetch()"
      />
      <p
        v-else-if="!invitations.data.value?.length && !joinState.loading && !joinState.pendingCount && !joinState.error"
        class="text-meta text-muted"
      >
        No pending invitations.
      </p>
      <div
        v-else
        class="grid gap-3 xl:grid-cols-2"
      >
        <article
          v-for="inv in invitations.data.value"
          :key="inv.id"
          class="min-w-0 rounded-xl border border-dashed border-line bg-surface-subtle p-4 [overflow-wrap:anywhere]"
        >
          <p class="text-body font-medium">
            {{ inv.email }}
          </p>
          <p class="mt-2 text-meta text-muted">
            {{ inv.status === 'pending' ? 'Pending invitation' : presentLabel(inv.status) }} · {{ presentLabel(inv.role) }}
          </p>
        </article>
      </div>
    </section>

    <p class="border-t border-line pt-4 text-meta text-muted">
      Choose how others can reimburse you in <RouterLink
        :to="{ name: 'settings', hash: '#payment-links-settings' }"
        class="min-h-11 inline-flex items-center rounded-lg text-brand underline focus-ring"
      >
        My payment preferences
      </RouterLink>.
    </p>
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
