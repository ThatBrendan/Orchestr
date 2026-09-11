<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { storeToRefs } from "pinia";
import { useAuthStore } from "@/stores/auth";
import { useInvitation } from "@/composables/useInvitation";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import { APP_NAME } from "@/config";
import orchestrioIcon from "@/assets/orchestrio-icon.svg";
import AppButton from "@/components/ui/AppButton.vue";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const { ready, isAuthenticated } = storeToRefs(auth);
const toast = useToast();

const token = computed(() => String(route.params.token));
const authQuery = computed(() => ({ redirect: route.fullPath }));

// Preview requires auth (get_invitation is email-gated). Only fetch when signed in.
const { preview, accept: acceptMutation, decline: declineMutation } = useInvitation(token, {
  enabled: () => ready.value && isAuthenticated.value,
});

async function decline() {
  try {
    await declineMutation.mutateAsync();
    toast.success("Invitation declined.");
    await router.replace({ name: "projects" });
  } catch (e) { toast.error(toAppError(e).message); }
}

async function accept() {
  try {
    const projectId = await acceptMutation.mutateAsync();
    toast.success("You've joined the project.");
    await router.replace({ name: "project.overview", params: { projectId } });
  } catch (e) {
    toast.error(toAppError(e).message);
  }
}
</script>

<template>
  <div class="min-h-screen flex items-center justify-center px-6 bg-paper">
    <div class="w-full max-w-sm fade-in text-center">
      <img
        :src="orchestrioIcon"
        :alt="APP_NAME"
        class="mx-auto h-10 w-auto"
      >

      <!-- signed out: send the user through password auth, then back here -->
      <template v-if="ready && !isAuthenticated">
        <p class="mt-4 text-14 text-ink-soft">
          You've been invited to a project. Sign in to accept.
        </p>
        <div class="mt-6 grid gap-3">
          <AppButton
            :to="{ name: 'login', query: authQuery }"
            block
          >
            Log in
          </AppButton>
          <AppButton
            :to="{ name: 'signup', query: authQuery }"
            variant="secondary"
            block
          >
            Create account
          </AppButton>
        </div>
      </template>

      <!-- signed in -->
      <template v-else-if="ready && isAuthenticated">
        <div
          v-if="preview.isPending.value"
          class="mt-6 text-14 text-muted"
        >
          Loading invitation…
        </div>
        <div
          v-else-if="!preview.data.value"
          class="mt-6 border rounded-xl p-6 border-line bg-surface"
        >
          <p class="text-14 text-ink-soft">
            This invitation is invalid, expired, or was sent to a different email address.
          </p>
        </div>
        <div
          v-else
          class="mt-6 border rounded-xl p-6 border-line bg-surface"
        >
          <p class="text-14 text-ink-soft">
            <span class="font-medium text-ink">{{ preview.data.value.inviter_name ?? "Someone" }}</span>
            invited you to
            <span class="font-medium text-ink">{{ preview.data.value.project_name }}</span>
            as a {{ preview.data.value.role }}.
          </p>
          <AppButton
            class="mt-4"
            :loading="acceptMutation.isPending.value"
            :disabled="declineMutation.isPending.value"
            block
            @click="accept"
          >
            Accept invitation
          </AppButton>
          <AppButton
            class="mt-2"
            variant="secondary"
            :loading="declineMutation.isPending.value"
            :disabled="acceptMutation.isPending.value"
            block
            @click="decline"
          >
            Decline
          </AppButton>
        </div>
      </template>
    </div>
  </div>
</template>
