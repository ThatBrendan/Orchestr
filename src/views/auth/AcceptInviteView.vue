<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { storeToRefs } from "pinia";
import { useAuthStore } from "@/stores/auth";
import { useAuth } from "@/composables/useAuth";
import { useInvitation } from "@/composables/useInvitation";
import { useToast } from "@/composables/useToast";
import { toAppError } from "@/lib/errors";
import { APP_NAME } from "@/config";
import AppButton from "@/components/ui/AppButton.vue";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const { ready, isAuthenticated } = storeToRefs(auth);
const { signInWithOtp } = useAuth();
const toast = useToast();

const token = computed(() => String(route.params.token));
const email = ref("");
const busy = ref(false);
const linkSent = ref(false);

// Preview requires auth (get_invitation is email-gated). Only fetch when signed in.
const { preview, accept: acceptMutation } = useInvitation(token, {
  enabled: () => ready.value && isAuthenticated.value,
});

async function sendLink() {
  if (!email.value) return;
  busy.value = true;
  try {
    await signInWithOtp(email.value.trim());
    linkSent.value = true;
  } catch (e) {
    toast.error(toAppError(e).message);
  } finally {
    busy.value = false;
  }
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
      <div class="font-display font-semibold text-[20px] tracking-tight">{{ APP_NAME }}</div>

      <!-- signed out: gather the email to send an OTP -->
      <template v-if="ready && !isAuthenticated">
        <p class="mt-4 text-14 text-ink-soft">You've been invited to a project. Sign in to accept.</p>
        <div v-if="linkSent" class="mt-6 border rounded-xl p-6 border-line bg-surface">
          <p class="text-14 text-ink-soft">Check <span class="font-medium">{{ email }}</span> for a link, then reopen this invitation.</p>
        </div>
        <form v-else class="mt-6 space-y-3" @submit.prevent="sendLink">
          <input
            v-model="email"
            type="email"
            required
            placeholder="Your email"
            class="w-full border rounded-lg px-3.5 py-2.5 text-14 focus-ring border-line bg-surface"
          />
          <AppButton type="submit" :loading="busy" block>Send sign-in link</AppButton>
        </form>
      </template>

      <!-- signed in -->
      <template v-else-if="ready && isAuthenticated">
        <div v-if="preview.isPending.value" class="mt-6 text-14 text-muted">Loading invitation…</div>
        <div v-else-if="!preview.data.value" class="mt-6 border rounded-xl p-6 border-line bg-surface">
          <p class="text-14 text-ink-soft">This invitation is invalid, expired, or was sent to a different email address.</p>
        </div>
        <div v-else class="mt-6 border rounded-xl p-6 border-line bg-surface">
          <p class="text-14 text-ink-soft">
            <span class="font-medium text-ink">{{ preview.data.value.inviter_name ?? "Someone" }}</span>
            invited you to
            <span class="font-medium text-ink">{{ preview.data.value.project_name }}</span>
            as a {{ preview.data.value.role }}.
          </p>
          <AppButton class="mt-4" :loading="acceptMutation.isPending.value" block @click="accept">Accept invitation</AppButton>
        </div>
      </template>
    </div>
  </div>
</template>
