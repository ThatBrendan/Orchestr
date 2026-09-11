<script setup lang="ts">
import { computed, watch } from "vue";
import { useRoute } from "vue-router";
import { APP_NAME, PUBLIC_CONTACT_EMAIL } from "@/config";
import { setPageMeta } from "@/composables/usePageMeta";
import MarketingHeader from "@/components/marketing/MarketingHeader.vue";
import MarketingFooter from "@/components/marketing/MarketingFooter.vue";

type PageKind = "about" | "privacy" | "terms";
type ContentSection = { heading: string; paragraphs: string[]; items?: string[] };

const route = useRoute();
const updated = "10 September 2026";
const contact = PUBLIC_CONTACT_EMAIL || "A public privacy/support email address still needs to be configured.";

const content: Record<PageKind, { eyebrow: string; title: string; description: string; sections: ContentSection[] }> = {
  about: {
    eyebrow: "About Orchestrio",
    title: "Turn scattered plans into organised execution.",
    description: "Orchestrio is a planning and execution workspace built to help people turn scattered plans into organised action.",
    sections: [
      {
        heading: "Why I started building it",
        paragraphs: [
          "I kept seeing the same problem: planning rarely happens in one place. Plans end up spread across WhatsApp, email, spreadsheets, notes, documents, calendars and different people.",
          "The original idea grew from wanting a better way to coordinate plans without constantly piecing together information from different tools and conversations.",
        ],
      },
      {
        heading: "The problem",
        paragraphs: [
          "The information usually exists. It is just difficult to see the whole picture. Deadlines get missed, ownership becomes unclear, costs are hard to track and people spend too much time asking for updates.",
          "That makes it difficult to answer simple questions: What still needs to be done? Who owns it? When is it due? What has been paid? What changed? Are we actually ready?",
        ],
      },
      {
        heading: "What Orchestrio is trying to do",
        paragraphs: [
          "Orchestrio brings activities, responsibilities, timelines, people, costs and progress into one place, while adapting to the type of project being planned.",
          "The aim is to help people move from idea to planning to ownership to execution without requiring a collection of disconnected tools.",
        ],
      },
      {
        heading: "Where it is going",
        paragraphs: [
          "The goal is to make Orchestrio useful for both one-off plans and repeatable processes: group trips, weddings and events, house moves, team projects, product launches and recurring business workflows.",
        ],
      },
    ],
  },
  privacy: {
    eyebrow: "Privacy",
    title: "How Orchestrio handles information.",
    description: "Learn how Orchestrio handles account and project information.",
    sections: [
      {
        heading: "Information you provide",
        paragraphs: [
          "Orchestrio may store account details such as your email address and display name, along with the project information you choose to enter.",
          "This can include activities, tasks, members and invitations, notes, milestones, budgets, payment-planning information and project or profile images where those features are used.",
        ],
      },
      {
        heading: "Information collected automatically",
        paragraphs: [
          "Authentication and session information is handled through Supabase. Hosting and infrastructure providers may process basic technical request information, such as IP address, browser and device details, and service logs.",
          "We do not currently advertise or use a separate analytics service in this application.",
        ],
      },
      {
        heading: "Why information is used",
        paragraphs: [
          "Information is used to provide and secure Orchestrio, authenticate accounts, save and synchronise projects, support collaboration, troubleshoot errors, maintain the service and send service-related communications.",
        ],
      },
      {
        heading: "Service providers",
        paragraphs: [
          "Orchestrio uses Supabase for database, authentication and supported storage services, and Vercel for hosting and delivery. These providers process information as needed to provide their infrastructure services.",
          "Orchestrio does not sell your information. Project information may be visible to other members of the project when you invite or otherwise authorise them.",
        ],
      },
      {
        heading: "Retention and your choices",
        paragraphs: [
          "Information is retained while it is needed to provide the service, operate the product and meet applicable operational or legal obligations. Deletion and recovery behaviour may depend on the product feature involved.",
          "You can update available account and project information in the product. To request access, correction or deletion, contact Orchestrio using the privacy contact below.",
        ],
      },
      {
        heading: "Security",
        paragraphs: [
          "Orchestrio uses reasonable technical and organisational measures and trusted infrastructure providers to protect information. No online service can guarantee that information will be completely secure.",
        ],
      },
      {
        heading: "Contact",
        paragraphs: [contact],
      },
    ],
  },
  terms: {
    eyebrow: "Terms",
    title: "Terms for using Orchestrio.",
    description: "Terms for using Orchestrio.",
    sections: [
      {
        heading: "Using Orchestrio",
        paragraphs: [
          "You may use Orchestrio to create and manage projects, activities, tasks, people, timelines, budgets, notes and other planning information for lawful purposes.",
        ],
      },
      {
        heading: "Account responsibility",
        paragraphs: [
          "You are responsible for maintaining access to your account, providing accurate information where appropriate and activity performed through your account. Keep your sign-in details private and tell us if you believe your account has been compromised.",
        ],
      },
      {
        heading: "Acceptable use",
        paragraphs: ["Do not use Orchestrio for illegal activity, abuse, unauthorised access, malicious automation, attempts to compromise security or activity that disrupts the service or other users."],
      },
      {
        heading: "Your content and collaboration",
        paragraphs: [
          "You retain ownership of the content you enter. You give Orchestrio only the rights needed to host, process and display that content so the service can operate.",
          "Projects may contain information shared with invited members. Only add people and information you are authorised to use and share.",
        ],
      },
      {
        heading: "Availability and changes",
        paragraphs: [
          "Orchestrio is an evolving, early-stage service. Features may change, and maintenance or outages may occur. Uninterrupted availability is not guaranteed.",
        ],
      },
      {
        heading: "Restrictions and termination",
        paragraphs: [
          "We may restrict or suspend access where reasonably necessary to address serious misuse, security concerns or legal requirements. You may stop using the service at any time.",
        ],
      },
      {
        heading: "Disclaimers",
        paragraphs: [
          "Orchestrio is a planning and coordination tool, not professional financial, legal, safety, medical or other regulated advice. Use your own judgement and verify important information.",
          "The service is provided as an evolving product, subject to applicable law, without promises that every feature will always be available or error-free.",
        ],
      },
      {
        heading: "Changes and contact",
        paragraphs: [
          "These terms may be updated as Orchestrio develops. The updated date below will change when material updates are made.",
          contact,
        ],
      },
    ],
  },
};

const kind = computed<PageKind>(() => (route.name as PageKind) ?? "about");
const page = computed(() => content[kind.value]);
const isAbout = computed(() => kind.value === "about");
watch(
  [kind, page],
  ([currentKind, currentPage]) => {
    setPageMeta({ title: `${currentPage.eyebrow} · ${APP_NAME}`, description: currentPage.description });
    if (currentKind !== "about") window.scrollTo({ top: 0, behavior: "auto" });
  },
  { immediate: true },
);
</script>

<template>
  <div class="min-h-screen bg-paper">
    <MarketingHeader />
    <main
      id="main"
      class="max-w-6xl mx-auto px-5 md:px-8 py-14 md:py-20"
    >
      <article class="max-w-3xl mx-auto">
        <p class="text-13 font-semibold uppercase tracking-wide text-accent">
          {{ page.eyebrow }}
        </p>
        <h1 class="mt-3 font-display text-[34px] leading-tight font-semibold tracking-tight md:text-[46px]">
          {{ page.title }}
        </h1>
        <p class="mt-5 max-w-2xl text-[17px] leading-relaxed text-ink-soft">
          {{ page.description }}
        </p>

        <div class="mt-12 space-y-10">
          <section
            v-for="section in page.sections"
            :key="section.heading"
            :aria-labelledby="section.heading"
          >
            <h2
              :id="section.heading"
              class="font-display text-[22px] font-semibold tracking-tight"
            >
              {{ section.heading }}
            </h2>
            <p
              v-for="paragraph in section.paragraphs"
              :key="paragraph"
              class="mt-3 text-[15px] leading-7 text-ink-soft"
            >
              {{ paragraph }}
            </p>
          </section>
        </div>

        <p class="mt-12 border-t border-line pt-5 text-13 text-muted">
          Last updated: {{ updated }}
        </p>
        <p
          v-if="isAbout"
          class="mt-3 text-13 text-muted"
        >
          Built with a practical, founder-led approach.
        </p>
      </article>
    </main>
    <MarketingFooter />
  </div>
</template>