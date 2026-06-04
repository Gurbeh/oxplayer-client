import Container from "@/components/ui/Container";
import {
  PRIVACY_EFFECTIVE_DATE,
  PRIVACY_PACKAGE_ID,
  privacyDeleteBotUrl,
  privacyIssuesUrl,
  privacyRepoUrl,
  telegramPrivacyUrl,
} from "@/content/privacy-policy";
import Link from "next/link";

export default function PrivacyPolicyPage() {
  return (
    <div className="min-h-screen bg-slate-950 text-slate-200 py-12">
      <Container className="max-w-3xl">
        <nav className="mb-8 flex flex-wrap gap-4 text-sm">
          <Link href="/" className="text-primary hover:underline">
            ← Home
          </Link>
          <a href="#en" className="hover:text-primary">
            English
          </a>
          <a href="#fa" className="hover:text-primary">
            فارسی
          </a>
        </nav>

        <section id="en" lang="en" className="privacy-prose">
          <h1>OXPlayer Privacy Policy</h1>
          <p className="privacy-meta">
            Effective date: {PRIVACY_EFFECTIVE_DATE} · App package:{" "}
            <code>{PRIVACY_PACKAGE_ID}</code>
          </p>

          <p>
            This policy describes how <strong>OXPlayer</strong> (“the app”), a
            Telegram-connected media library client for Android (and related
            builds), handles information when you use the app. OXPlayer is
            published by the developer of the{" "}
            <a href={privacyRepoUrl}>oxplayer-client</a> project.
          </p>

          <h2>1. Who we are</h2>
          <p>
            The app connects to an <strong>OXPlayer backend API</strong> (URL
            configured at build time, e.g. your operator’s server) and to{" "}
            <strong>Telegram</strong> for sign-in and media access. For privacy
            questions or requests, contact us via{" "}
            <a href={privacyIssuesUrl}>GitHub Issues</a> on the repository above
            (preferred) or the support channel listed on your Play Store
            listing.
          </p>

          <h2>2. Information we collect and use</h2>
          <ul>
            <li>
              <strong>Telegram account data</strong> To sign you in, the app
              uses Telegram (TDLib / Mini App <code>initData</code>). We send
              signed authentication data to the OXPlayer API (
              <code>POST /auth/telegram</code>) to obtain an access token. This
              typically includes your Telegram user identifier and profile
              fields Telegram provides in <code>initData</code>. Telegram’s own{" "}
              <a href={telegramPrivacyUrl}>Privacy Policy</a> applies to
              Telegram’s services.
            </li>
            <li>
              <strong>Library and playback data</strong> Watch progress,
              favorites, library items, search queries, and related media
              metadata are requested from and stored on the OXPlayer API as
              needed to operate your account (Jellyfin-compatible API).
            </li>
            <li>
              <strong>Metadata from third-party catalogs</strong> Title
              descriptions, posters, and similar metadata may be loaded via the
              OXPlayer API (e.g. TMDB-backed endpoints). TMDB’s policies apply
              to their content; we do not sell this data.
            </li>
            <li>
              <strong>Data on your device</strong> Session tokens, TDLib session
              state, cached images, and app preferences may be stored locally on
              your phone or tablet for performance and offline resilience.
            </li>
            <li>
              <strong>Technical data</strong> Standard HTTPS requests include IP
              address and device/app information required to deliver the
              service. We do not embed third-party advertising or analytics SDKs
              in the open-source client build described in this repository.
            </li>
          </ul>

          <h2>3. How we use information</h2>
          <ul>
            <li>Authenticate you and keep you signed in</li>
            <li>Stream and organize your media library</li>
            <li>Sync playback progress and user-specific settings</li>
            <li>
              Operate, secure, and improve the service (e.g. fixing errors
              reported by users)
            </li>
          </ul>

          <h2>4. Sharing</h2>
          <p>
            We do not sell your personal information. Data may be processed by:
          </p>
          <ul>
            <li>
              <strong>Telegram</strong> authentication and Telegram-hosted media
              flows you initiate
            </li>
            <li>
              <strong>OXPlayer API operator</strong> the server that hosts your
              account data
            </li>
            <li>
              <strong>Infrastructure providers</strong> hosting/CDN used by that
              API (under their terms)
            </li>
            <li>
              <strong>Metadata providers</strong> e.g. TMDB for artwork and
              descriptions, as routed by the API
            </li>
          </ul>
          <p>
            We may disclose information if required by law or to protect rights,
            safety, and security.
          </p>

          <h2 id="account-deletion">5. Retention and deletion</h2>
          <p>
            Server-side retention depends on the OXPlayer API operator. You may
            sign out in the app to remove local tokens on the device.
          </p>
          <h3>Delete your account</h3>
          <p>
            You can delete your OXPlayer server account and associated data
            without contacting support.
          </p>
          <ol>
            <li>
              <strong>In the app:</strong> Settings → Profile →{" "}
              <em>Delete account</em>, then confirm.
            </li>
            <li>
              <strong>In Telegram:</strong> open{" "}
              <a href={privacyDeleteBotUrl}>@OXPlayerBot</a> with the delete
              link, tap <em>Yes, delete</em> when asked to confirm.
            </li>
          </ol>
          <p>
            Deletion revokes API sessions and tombstones your user record so
            your Telegram id can be used for a new account on a later sign-in.
            For other access or privacy requests, contact us via GitHub Issues.
          </p>

          <h2>6. Security</h2>
          <p>
            Traffic uses HTTPS where supported. You are responsible for keeping
            your device and Telegram account secure. No method of transmission
            or storage is 100% secure.
          </p>

          <h2>7. Children</h2>
          <p>
            OXPlayer is not directed at children under 13 (or the minimum age in
            your country). We do not knowingly collect personal information from
            children.
          </p>

          <h2>8. International transfers</h2>
          <p>
            Your data may be processed in countries where the API, Telegram, or
            metadata providers operate. By using the app, you understand that
            these transfers may occur.
          </p>

          <h2>9. Changes</h2>
          <p>
            We may update this policy. The effective date at the top will
            change. Continued use after updates means you accept the revised
            policy.
          </p>

          <h2>10. Your rights</h2>
          <p>
            Depending on your region (e.g. GDPR), you may have rights to access,
            correct, delete, or restrict processing of your data. Contact us via
            GitHub Issues to exercise these rights.
          </p>
        </section>

        <hr className="my-12 border-slate-700" />

        <section id="fa" lang="fa" dir="rtl" className="privacy-prose">
          <h1>سیاست حریم خصوصی OXPlayer</h1>
          <p className="privacy-meta">
            تاریخ اجرا: ۲۱ مه ۲۰۲۶ · شناسهٔ بسته:{" "}
            <code>{PRIVACY_PACKAGE_ID}</code>
          </p>

          <p>
            این سند توضیح می‌دهد اپلیکیشن <strong>OXPlayer</strong> (کلاینت
            کتابخانهٔ رسانه با اتصال تلگرام) چگونه اطلاعات را هنگام استفاده از
            اپ پردازش می‌کند.
          </p>

          <h2>۱. مسئول سرویس</h2>
          <p>
            اپ به <strong>سرور API مربوط به OXPlayer</strong> و{" "}
            <strong>تلگرام</strong> برای ورود و دسترسی به رسانه متصل می‌شود.
            برای سوال یا درخواست حریم خصوصی از{" "}
            <a href={privacyIssuesUrl}>GitHub Issues</a> در مخزن پروژه استفاده
            کنید.
          </p>

          <h2>۲. داده‌های جمع‌آوری‌شده</h2>
          <ul>
            <li>
              <strong>حساب تلگرام</strong> ورود با TDLib / Mini App و ارسال{" "}
              <code>initData</code> به API برای دریافت توکن
            </li>
            <li>
              <strong>کتابخانه و پخش</strong> پیشرفت تماشا، علاقه‌مندی‌ها و
              متادیتا روی سرور OXPlayer
            </li>
            <li>
              <strong>متادیتای شخص ثالث</strong> مثلاً پوستر و توضیحات از مسیر
              API (TMDB)
            </li>
            <li>
              <strong>داده روی دستگاه</strong> توکن، نشست TDLib و کش محلی
            </li>
            <li>
              <strong>داده فنی</strong> IP و اطلاعات لازم HTTPS؛ بدون SDK
              تبلیغات/آنالیتیکس شخص ثالث در بیلد متن‌باز این مخزن
            </li>
          </ul>

          <h2>۳. استفاده از داده</h2>
          <ul>
            <li>احراز هویت و نگه‌داشتن ورود</li>
            <li>پخش و سازمان‌دهی کتابخانه</li>
            <li>همگام‌سازی پیشرفت تماشا و تنظیمات</li>
            <li>نگهداری و امنیت سرویس</li>
          </ul>

          <h2>۴. اشتراک‌گذاری</h2>
          <p>
            اطلاعات شخصی فروخته نمی‌شود. پردازش ممکن است توسط تلگرام، اپراتور
            API، میزبان و ارائه‌دهندگان متادیتا (مثل TMDB) انجام شود.
          </p>

          <h2 id="account-deletion-fa">۵. نگهداری و حذف</h2>
          <p>خروج از اپ توکن محلی را حذف می‌کند.</p>
          <h3>حذف حساب</h3>
          <p>
            می‌توانید حساب سرور OXPlayer و داده‌های مرتبط را بدون تماس با
            پشتیبانی حذف کنید:
          </p>
          <ol>
            <li>
              <strong>در اپ:</strong> تنظیمات → پروفایل → <em>حذف حساب</em>، سپس
              تأیید.
            </li>
            <li>
              <strong>در تلگرام:</strong>{" "}
              <a href={privacyDeleteBotUrl}>@OXPlayerBot</a> را با لینک حذف باز
              کنید و <em>بله، حذف کن</em> را بزنید.
            </li>
          </ol>
          <p>
            حذف، نشست‌های API را لغو و رکورد کاربر را علامت‌گذاری می‌کند تا
            شناسهٔ تلگرام برای ورود بعدی قابل استفاده باشد.
          </p>

          <h2>۶. امنیت، کودکان، انتقال بین‌المللی</h2>
          <p>
            ارتباط ترجیحاً HTTPS است. اپ برای کودکان زیر ۱۳ سال هدف‌گذاری نشده
            است. داده ممکن است در کشورهای مربوط به API، تلگرام یا ارائه‌دهندگان
            متادیتا پردازش شود.
          </p>

          <h2>۷. تغییرات و حقوق</h2>
          <p>
            این سیاست ممکن است به‌روز شود. بسته به قوانین منطقه (مثل GDPR)
            می‌توانید حق دسترسی، اصلاح یا حذف را از طریق GitHub Issues درخواست
            کنید.
          </p>
        </section>
      </Container>
    </div>
  );
}
