<script setup lang="ts">
import { computed, ref } from "vue";
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

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { members, isPending, isError, error, refetch } = useMemberDirectory(projectId);
const { allowed, project } = useProjectContext();
const toast = useToast();

const roster = computed(() => members.value.filter((m) => m.status !== "removed"));
const removedCount = computed(() => members.value.length - roster.value.length);
const archived = computed(() => project.value?.status === "archived");
const canManage = computed(() => allowed("members.manage") && !archived.value);
const canInvite = computed(() => allowed("project.invite") && !archived.value);

const updateRole = useUpdateMemberRole(projectId.value);
const removeMember = useRemoveMember(projectId.value);

const rowError = ref<Record<string, string>>({});
const inviteOpen = ref(false);
const confirmRemove = ref<{ id: string; name: string } | null>(null);

async function onRoleChange(memberId: string, role: MemberRole) {
  rowError.value = { ...rowError.value, [memberId]: "" };
  try {
    await updateRole.mutateAsync({ memberId, role });
    toast.success("Role updated.");
  } catch (e) {
    rowError.value = { ...rowError.value, [memberId]: toAppError(e).message };
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
    <div v-if="isPending" class="space-y-2">
      <SkeletonBlock v-for="i in 4" :key="i" height="56px" rounded="0.5rem" />
    </div>
    <ErrorState v-else-if="isError" :error="error" :retry="() => refetch()" />
    <template v-else>
      <div class="flex items-center justify-between mb-4">
        <p class="text-14 text-ink-soft">{{ roster.length }} {{ roster.length === 1 ? "person" : "people" }}</p>
        <AppButton v-if="canInvite" size="sm" @click="inviteOpen = true">Invite</AppButton>
      </div>

      <EmptyState v-if="roster.length === 0" message="No one has been added to this project yet.">
        <template v-if="canInvite" #action>
          <AppButton size="sm" @click="inviteOpen = true">Invite someone</AppButton>
        </template>
      </EmptyState>

      <div v-else class="border rounded-xl divide-y border-line bg-surface">
        <div v-for="m in roster" :key="m.member_id" class="px-4 py-3.5">
          <div class="flex items-center gap-3.5">
            <AppAvatar :name="m.display_name" :url="m.avatar_url" :size="36" />
            <div class="min-w-0 flex-1">
              <div class="text-14 font-medium">{{ m.display_name }}</div>
              <div class="text-13 text-muted capitalize">{{ m.role }}</div>
            </div>
            <StatusBadge v-if="m.status === 'invited'" label="Invited" :tone="statusTone(m.status)" />

            <select
              v-if="canManage"
              class="border rounded-lg px-2 py-1.5 text-13 focus-ring border-line bg-surface"
              :value="m.role"
              @change="onRoleChange(m.member_id, ($event.target as HTMLSelectElement).value as MemberRole)"
            >
              <option value="organizer">Organizer</option>
              <option value="member">Member</option>
              <option value="viewer">Viewer</option>
            </select>
            <StatusBadge v-else-if="m.role === 'organizer'" label="Organizer" :tone="roleTone(m.role)" />

            <AppButton
              v-if="canManage"
              variant="secondary"
              size="sm"
              @click="confirmRemove = { id: m.member_id, name: m.display_name }"
            >
              Remove
            </AppButton>
          </div>
          <p v-if="rowError[m.member_id]" class="mt-2 text-13 text-danger">{{ rowError[m.member_id] }}</p>
        </div>
      </div>
      <p v-if="removedCount > 0" class="mt-3 text-13 text-muted">
        {{ removedCount }} former {{ removedCount === 1 ? "member has" : "members have" }} been removed.
      </p>
      <p v-if="archived" class="mt-3 text-13 text-amber">This project is archived — membership is read-only.</p>
    </template>

    <InviteMemberDialog :open="inviteOpen" :project-id="projectId" @close="inviteOpen = false" />
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
