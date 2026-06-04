"use client";
import "swiper/css";
import "swiper/css/pagination";
import { Autoplay, Pagination } from "swiper/modules";
import { Swiper, SwiperSlide } from "swiper/react";
import Image from "next/image";
import Heading from "@/components/ui/Heading";
import Container from "@/components/ui/Container";
import { FaStar } from "react-icons/fa";
import Paragraph from "@/components/ui/Paragraph";

import { assetPath } from "@/config/site";
import "../home.css";

const data = [
  {
    message:
      "OXPlayer changed how I manage my Telegram videos. Scattered files across chats are now organized into a beautiful library with posters, metadata, and seamless playback.",
    name: "Mark Thompson",
    image: assetPath("/images/person-2.jpg"),
  },
  {
    message:
      "I love how easy it is to send a movie to the bot and have it automatically appear in my library. The Netflix-style interface makes browsing my collection a pleasure.",
    name: "Jane Smith",
    image: assetPath("/images/person-1.jpg"),
  },
  {
    message:
      "The watchlist and resume playback features are fantastic. I can start a movie on one device and continue exactly where I left off later. OXPlayer feels incredibly polished.",
    name: "John Doe",
    image: assetPath("/images/person-3.jpg"),
  },
  {
    message:
      "I've tried different ways to manage Telegram videos, but nothing comes close to OXPlayer. Automatic organization and rich movie details make my collection look professional.",
    name: "Mike Johnson",
    image: assetPath("/images/person-4.jpg"),
  },
  {
    message:
      "The search experience is incredibly fast, and finding movies has never been easier. OXPlayer turns Telegram into a complete personal streaming platform that I use every day.",
    name: "Sarah Williams",
    image: assetPath("/images/person-5.jpg"),
  },
];

const Reviews = () => {
  return (
    <section className="pt-24 lg:pt-40">
      <Container>
        <Heading level="h2" align="center" className=" !text-gray-100 mb-5">
          Our Happy Users
        </Heading>

        <div className="cursor-pointer relative">
          <Swiper
            className="mySwiper"
            slidesPerView={3}
            spaceBetween={5}
            modules={[Pagination, Autoplay]}
            pagination={{
              clickable: true,
              el: ".swiper-pagination",
            }}
            autoplay={{
              delay: 6000,
              disableOnInteraction: false,
            }}
            breakpoints={{
              300: {
                slidesPerView: 1,
                spaceBetween: 10,
              },
              768: {
                slidesPerView: 2,
                spaceBetween: 20,
              },
              1280: {
                slidesPerView: 3,
                spaceBetween: 20,
              },
            }}
          >
            {data &&
              data?.length > 0 &&
              data.map((item, index) => (
                <div key={item.name}>
                  <SwiperSlide key={item.message} className="pb-16">
                    <div className="bg-slate-900 border border-slate-700 p-5 sm:p-10 md:p-5 lg:p-10 rounded-xl md:min-h-[390px] lg:min-h-[370px]">
                      <div className="flex gap-5 items-center">
                        <div className="relative rounded-full h-[60px] w-[60px] sm:h-[80px] sm:w-[80px]">
                          <Image src={item.image} alt="image" fill className="object-cover rounded-full" />
                        </div>
                        <Heading level="h6" size="md">
                          {item.name}
                        </Heading>
                      </div>

                      <div className="flex gap-2 mt-5 mb-3">
                        <FaStar className="text-primary text-2xl sm:text-3xl" />
                        <FaStar className="text-primary text-2xl sm:text-3xl" />
                        <FaStar className="text-primary text-2xl sm:text-3xl" />
                        <FaStar className="text-primary text-2xl sm:text-3xl" />
                        <FaStar className="text-primary text-2xl sm:text-3xl" />
                      </div>

                      <Paragraph>{item.message}</Paragraph>
                    </div>
                  </SwiperSlide>
                </div>
              ))}
          </Swiper>

          <div className="swiper-pagination absolute  -bottom-[10px] left-24 mt-5"></div>
        </div>
      </Container>
    </section>
  );
};

export default Reviews;
