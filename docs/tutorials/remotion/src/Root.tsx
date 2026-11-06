import React from "react";
import { Composition } from "remotion";
import { TodayFlowTutorial } from "./Tutorial";
import { TodayFlowUseCases } from "./UseCases";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="TodayFlowOverview"
        component={TodayFlowTutorial}
        durationInFrames={900}
        fps={30}
        width={1280}
        height={720}
      />
      <Composition
        id="TodayFlowUseCases"
        component={TodayFlowUseCases}
        durationInFrames={1280}
        fps={30}
        width={1280}
        height={720}
      />
    </>
  );
};
