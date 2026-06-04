import { assetPath } from "@/config/site";
import Image from "next/image";

const AppShowcase = () => {
  return (
    <section className="relative pt-7 md:pt-10 xl:pt-10">
      {/* Movie Images */}
      <div className="relative">
        <div className="w-[400px] h-[400px] sm:w-[500px] sm:h-[500px] md:w-[900px] md:h-[700px] absolute -top-10 left-1/2 -translate-x-1/2 bg-gradient-to-r from-secondary to-primary blur-3xl opacity-30   rounded-full z-0 border-8"></div>
        <div className="relative h-[250px] sm:h-[450px] lg:h-[600px] xl:h-[650px] z-10">
          <Image
            src={assetPath("/images/cinema-3.png")}
            alt="movie-scene"
            fill
            className="object-cover"
          />
        </div>
      </div>

      <div className="absolute -top-5 sm:-top-10 md:-top-12 lg:-top-14 xl:-top-20 left-1/2 -translate-x-1/2 z-10">
        <div className="relative aspect-square w-[360px] sm:w-[600px] md:w-[650px] lg:w-[800px] xl:w-[900px]">
          <Image
            src={assetPath("/images/app-showcase-0.png")}
            alt="movie-scene"
            fill
            className="object-contain"
          />
        </div>
      </div>

      {/* <div className="bg-black/10 inset-0 w-full h-full absolute z-0"></div> */}
    </section>
  );
};

export default AppShowcase;
