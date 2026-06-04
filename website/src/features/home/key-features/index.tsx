import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import Paragraph from "@/components/ui/Paragraph";
import Image from "next/image";
import { assetPath } from "@/config/site";

const Box = ({ title, titlePosstion = "left", img, des }: any) => {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2">
      {/* BOX */}
      <div
        className={`border rounded-2xl p-5 sm:p-10 md:p-5 lg:p-10 relative flex flex-col justify-center  ${titlePosstion === "left" ? "max-md:order-1" : ""}`}
        style={{
          borderImage: "linear-gradient(to right, var(--color-primary), #FF6900, var(--color-secondary)) 1",
        }}
      >
        <div className=" bg-primary rounded-full w-[25px] h-[25px] absolute -top-[10px] -left-[13px] border-8 border-base-100"></div>
        <div className=" bg-primary rounded-full w-[25px] h-[25px] absolute -top-[10px] -right-[13px] border-8 border-base-100"></div>
        <div className=" bg-primary rounded-full w-[25px] h-[25px] absolute -bottom-[10px] -left-[13px] border-8 border-base-100"></div>
        <div className=" bg-primary rounded-full w-[25px] h-[25px] absolute -bottom-[10px] -right-[13px] border-8 border-base-100"></div>

        {titlePosstion === "left" ? (
          <>
            <Heading className="!text-gray-100">{title}</Heading>
            <Paragraph className="text-gray-400">{des}</Paragraph>
          </>
        ) : (
          <div className="relative w-full h-[280px] md:h-[400px] aspect-square">
            <Image src={img} alt="movie-scene" fill className="object-contain" />
          </div>
        )}
      </div>
      <div
        className={`border-t border-b border-r max-md:border-l rounded-2xl p-5 sm:p-10 relative flex flex-col justify-center ${titlePosstion === "right" ? "max-md:order-1" : ""}`}
        style={{
          borderImage: "linear-gradient(to right, var(--color-primary), #FF6900, var(--color-secondary)) 1",
        }}
      >
        <div className=" bg-primary rounded-full w-[25px] h-[25px] absolute -top-[10px] -left-[13px] border-8 border-base-100"></div>
        <div className=" bg-primary rounded-full w-[25px] h-[25px] absolute -top-[10px] -right-[13px] border-8 border-base-100"></div>
        <div className=" bg-primary rounded-full w-[25px] h-[25px] absolute -bottom-[10px] -left-[13px] border-8 border-base-100"></div>
        <div className=" bg-primary rounded-full w-[25px] h-[25px] absolute -bottom-[10px] -right-[13px] border-8 border-base-100"></div>

        {titlePosstion === "right" ? (
          <>
            <Heading className="!text-gray-100">{title}</Heading>
            <Paragraph className="text-gray-400">{des}</Paragraph>
          </>
        ) : (
          <div className="relative w-full h-[280px] md:h-[400px] aspect-square">
            <Image src={img} alt="movie-scene" fill className="object-contain" />
          </div>
        )}
      </div>
    </div>
  );
};

const KeyFeatures = () => {
  return (
    <section className="relative pt-24 lg:pt-40">
      <Container>
        <Box
          title="Personal Media Library"
          img={assetPath("/images/FT-1.png")}
          des="Turn your Telegram videos into a beautifully organized streaming library designed for effortless browsing. OXPlayer automatically enhances your collection with posters, movie information, and structured organization, making it easy to manage, discover, and enjoy all your content from a single, elegant interface."
        />

        <Box
          title="Smart Search & Discovery"
          titlePosstion="right"
          img={assetPath("/images/FT-2.png")}
          des="Spend less time searching and more time watching. OXPlayer provides powerful search capabilities, rich metadata, and intelligent organization to help you quickly find movies, TV shows, and videos. Discover content instantly through a clean, intuitive interface built for convenience."
        />

        <Box
          title="Favorites & Watchlist"
          img={assetPath("/images/FT-3.png")}
          des="Keep track of the content you love and the titles you want to watch next. Create personalized favorites and watchlists that stay synchronized with your account, allowing you to easily return to important content and build your own curated entertainment experience."
        />
      </Container>
    </section>
  );
};

export default KeyFeatures;
