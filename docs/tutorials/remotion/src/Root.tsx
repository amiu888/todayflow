import React from "react";
import { Composition } from "remotion";
import { TodayFlowTutorial } from "./Tutorial";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="TodayFlowOverview"
      component={TodayFlowTutorial}
      durationInFrames={900}
      fps={30}
      width={1280}
      height={720}
    />
  );
};
