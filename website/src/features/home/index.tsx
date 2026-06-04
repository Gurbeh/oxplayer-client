import Hero from "./hero";
import AppShowcase from "./app-showcase/AppShowcase";
import TelegramPrivacyNote from "./TelegramPrivacyNote";
import KeyFeatures from "./key-features";
import HowItWorks from "./how-it-works";
import WhyOX from "./why-ox";
import Footer from "./footer";
import FAQ from "./FAQ";
import Reviews from "./reviews";

const Home = () => {
  return (
    <div className="min-h-screen">
      <Hero />
      <AppShowcase />
      <TelegramPrivacyNote />
      <KeyFeatures />
      <HowItWorks />
      <WhyOX />
      <Reviews />
      <FAQ />
      <Footer />
    </div>
  );
};

export default Home;
