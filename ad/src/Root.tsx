import { Composition } from "remotion";
import { Ad } from "./Ad";

const FPS = 30;

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="ad"
      component={Ad}
      // 30 seconds is the cap the submission form sets for a product advertisement.
      durationInFrames={30 * FPS}
      fps={FPS}
      width={1920}
      height={1080}
    />
  );
};
