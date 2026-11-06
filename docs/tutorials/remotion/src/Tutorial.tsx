import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const colors = {
  background: "#07090f",
  surface: "#151f2e",
  text: "#f1f5f9",
  secondary: "#94a3b8",
  accent: "#60a5fa",
  violet: "#a78bfa",
};

const Scene: React.FC<{
  duration: number;
  children: React.ReactNode;
}> = ({ duration, children }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 12, duration - 12, duration], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

const Screenshot: React.FC<{
  file: string;
  label: string;
  detail: string;
  side?: "left" | "right";
}> = ({ file, label, detail, side = "right" }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 18, stiffness: 90 } });
  const y = interpolate(enter, [0, 1], [50, 0]);
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(circle at 22% 18%, #1b2b4a 0%, ${colors.background} 55%)`,
        flexDirection: side === "left" ? "row-reverse" : "row",
        alignItems: "center",
        padding: "54px 70px",
        gap: 54,
      }}
    >
      <Img
        src={staticFile(file)}
        style={{
          width: 400,
          maxHeight: 590,
          objectFit: "contain",
          borderRadius: 18,
          boxShadow: "0 30px 80px rgba(0,0,0,.55)",
          border: "1px solid rgba(255,255,255,.12)",
          transform: `translateY(${y}px) scale(${0.96 + enter * 0.04})`,
        }}
      />
      <div style={{ flex: 1 }}>
        <div
          style={{
            color: colors.accent,
            fontSize: 20,
            fontWeight: 700,
            letterSpacing: 2,
            textTransform: "uppercase",
            marginBottom: 18,
          }}
        >
          TodayFlow
        </div>
        <div
          style={{
            color: colors.text,
            fontSize: 52,
            lineHeight: 1.06,
            fontWeight: 800,
            letterSpacing: -1.5,
            transform: `translateY(${y}px)`,
          }}
        >
          {label}
        </div>
        <div
          style={{
            color: colors.secondary,
            fontSize: 24,
            lineHeight: 1.45,
            marginTop: 20,
            maxWidth: 560,
            transform: `translateY(${y * 0.7}px)`,
          }}
        >
          {detail}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const Title: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 16, stiffness: 80 } });
  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        background: `radial-gradient(circle at 50% 35%, #243f73 0%, ${colors.background} 62%)`,
        fontFamily: "Inter, -apple-system, BlinkMacSystemFont, sans-serif",
      }}
    >
      <div
        style={{
          fontSize: 104,
          fontWeight: 900,
          letterSpacing: -5,
          color: colors.text,
          transform: `scale(${0.9 + enter * 0.1})`,
          opacity: enter,
        }}
      >
        Today<span style={{ color: colors.accent }}>Flow</span>
      </div>
      <div
        style={{
          color: colors.secondary,
          fontSize: 30,
          marginTop: 18,
          opacity: enter,
          transform: `translateY(${interpolate(enter, [0, 1], [24, 0])}px)`,
        }}
      >
        Drag anything in. Keep the day moving.
      </div>
    </AbsoluteFill>
  );
};

export const TodayFlowTutorial: React.FC = () => {
  return (
    <AbsoluteFill style={{ fontFamily: "Inter, -apple-system, BlinkMacSystemFont, sans-serif" }}>
      <Sequence durationInFrames={90}>
        <Scene duration={90}>
          <Title />
        </Scene>
      </Sequence>
      <Sequence from={90} durationInFrames={170}>
        <Scene duration={170}>
          <Screenshot
            file="today-panel.png"
            label="Everything for today, in one slim panel."
            detail="Tasks, trays, projects, and filters stay visible. Drop an email, file, URL, or Jira ticket anywhere."
          />
        </Scene>
      </Sequence>
      <Sequence from={260} durationInFrames={160}>
        <Scene duration={160}>
          <Screenshot
            file="task-contact.png"
            label="Add a contact directly to a task."
            detail="Pick an existing person or type a name, email, and phone. Matching details reuse the existing contact."
            side="left"
          />
        </Scene>
      </Sequence>
      <Sequence from={420} durationInFrames={160}>
        <Scene duration={160}>
          <Screenshot
            file="today-panel-narrow.png"
            label="Squeeze it. It reflows."
            detail="The week strip turns vertical, trays stack as full-width columns, and the single-column layout scales to fit."
          />
        </Scene>
      </Sequence>
      <Sequence from={580} durationInFrames={180}>
        <Scene duration={180}>
          <Screenshot
            file="ai-setup.png"
            label="AI is optional. Local is first."
            detail="TodayFlow scans Ollama, LM Studio, llama.cpp, vLLM, and more. Or download a 533 MB tiny model. Nothing runs until you choose."
            side="left"
          />
        </Scene>
      </Sequence>
      <Sequence from={760} durationInFrames={140}>
        <Scene duration={140}>
          <AbsoluteFill
            style={{
              alignItems: "center",
              justifyContent: "center",
              background: `radial-gradient(circle at 50% 50%, #1d355f 0%, ${colors.background} 65%)`,
              textAlign: "center",
            }}
          >
            <div style={{ color: colors.text, fontSize: 64, fontWeight: 900, letterSpacing: -2 }}>
              Works without AI.
            </div>
            <div style={{ color: colors.violet, fontSize: 64, fontWeight: 900, letterSpacing: -2 }}>
              Better with it.
            </div>
            <div style={{ color: colors.secondary, fontSize: 26, marginTop: 26 }}>
              github.com/amiu888/todayflow
            </div>
          </AbsoluteFill>
        </Scene>
      </Sequence>
    </AbsoluteFill>
  );
};
