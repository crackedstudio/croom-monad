import { Composition } from "remotion";
import { Ad } from "./Ad";
import { FOUNDER_DEMO_DURATION_FRAMES, FounderDemo } from "./FoundationDemo";

const FPS = 30;

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="ad"
        component={Ad}
        // 30 seconds is the cap the submission form sets for a product advertisement.
        durationInFrames={30 * FPS}
        fps={FPS}
        width={1920}
        height={1080}
      />
      <Composition
        id="founder-demo"
        component={FounderDemo}
        durationInFrames={FOUNDER_DEMO_DURATION_FRAMES}
        fps={FPS}
        width={1920}
        height={1080}
      />
    </>
  );
};
