import PrivacyPolicyPage from "@/features/legal/PrivacyPolicyPage";
import { createPageMetadata } from "@/config/seo";

export const metadata = createPageMetadata({
  title: "Privacy Policy",
  description:
    "How OXPlayer handles your data when you use the Telegram-connected media library app.",
  path: "/privacy-policy",
});

export default function Page() {
  return <PrivacyPolicyPage />;
}
