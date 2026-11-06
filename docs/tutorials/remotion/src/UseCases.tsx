import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  OffthreadVideo,
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
  green: "#34d399",
  amber: "#fbbf24",
};

const font =
  "Inter, -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif";

const Backdrop: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill
    style={{
      background:
        "radial-gradient(circle at 18% 14%, #1b2b4a 0%, #0a1020 42%, #07090f 72%)",
      fontFamily: font,
    }}
  >
    <AbsoluteFill
      style={{
        backgroundImage:
          "linear-gradient(rgba(148,163,184,.055) 1px, transparent 1px), linear-gradient(90deg, rgba(148,163,184,.055) 1px, transparent 1px)",
        backgroundSize: "48px 48px",
        maskImage: "radial-gradient(circle at 50% 45%, black, transparent 78%)",
      }}
    />
    {children}
  </AbsoluteFill>
);

const Scene: React.FC<{
  duration: number;
  children: React.ReactNode;
}> = ({ duration, children }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(
    frame,
    [0, 12, duration - 12, duration],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

const Chapter: React.FC<{ index: string; label: string }> = ({ index, label }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 12,
      color: colors.accent,
      fontSize: 16,
      fontWeight: 800,
      letterSpacing: 2.4,
      textTransform: "uppercase",
    }}
  >
    <div
      style={{
        width: 30,
        height: 30,
        borderRadius: 9,
        background: "rgba(96,165,250,.16)",
        border: "1px solid rgba(96,165,250,.42)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        letterSpacing: 0,
      }}
    >
      {index}
    </div>
    {label}
  </div>
);

const Title: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 16, stiffness: 80 } });
  const sub = spring({
    frame: frame - 12,
    fps,
    config: { damping: 18, stiffness: 70 },
  });
  return (
    <Backdrop>
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
        }}
      >
        <div
          style={{
            fontSize: 88,
            fontWeight: 900,
            letterSpacing: -4,
            color: colors.text,
            transform: `scale(${0.92 + enter * 0.08})`,
            opacity: enter,
          }}
        >
          Today<span style={{ color: colors.accent }}>Flow</span> in action
        </div>
        <div
          style={{
            fontSize: 28,
            color: colors.secondary,
            marginTop: 18,
            opacity: sub,
            transform: `translateY(${interpolate(sub, [0, 1], [22, 0])}px)`,
          }}
        >
          Create a task. Drop an email or file. Automate a tray.
        </div>
        <div
          style={{
            marginTop: 42,
            display: "flex",
            gap: 12,
            fontSize: 15,
            fontWeight: 700,
            color: colors.text,
            opacity: sub,
          }}
        >
          {["CREATE", "DROP", "AUTOMATE"].map((label) => (
            <div
              key={label}
              style={{
                padding: "9px 16px",
                borderRadius: 999,
                background: "rgba(148,163,184,.12)",
                border: "1px solid rgba(148,163,184,.25)",
                letterSpacing: 1.6,
              }}
            >
              {label}
            </div>
          ))}
        </div>
      </AbsoluteFill>
    </Backdrop>
  );
};

const Step: React.FC<{
  number: number;
  children: React.ReactNode;
  active: boolean;
  done: boolean;
}> = ({ number, children, active, done }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 14,
      fontSize: 21,
      color: active || done ? colors.text : colors.secondary,
      opacity: active || done ? 1 : 0.62,
      transform: `translateX(${active ? 6 : 0}px)`,
      transition: "none",
    }}
  >
    <div
      style={{
        width: 30,
        height: 30,
        borderRadius: 15,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontSize: 14,
        fontWeight: 800,
        color: done ? "#052e1b" : active ? colors.background : colors.secondary,
        background: done ? colors.green : active ? colors.accent : "rgba(148,163,184,.16)",
        border: active ? `1px solid ${colors.accent}` : "1px solid transparent",
      }}
    >
      {done ? "✓" : number}
    </div>
    {children}
  </div>
);

const CreateTaskScene: React.FC = () => {
  const frame = useCurrentFrame();
  const step = frame < 70 ? 0 : frame < 125 ? 1 : 2;
  return (
    <Backdrop>
      <div style={{ position: "absolute", left: 74, top: 44 }}>
        <Chapter index="1" label="Create a task" />
      </div>
      <div
        style={{
          position: "absolute",
          left: 120,
          top: 120,
          width: 360,
          height: 468,
          borderRadius: 18,
          overflow: "hidden",
          border: "1px solid rgba(255,255,255,.14)",
          boxShadow: "0 34px 90px rgba(0,0,0,.55)",
        }}
      >
        <OffthreadVideo
          src={staticFile("use-cases/create-task.mp4")}
          startFrom={30}
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 560,
          top: 142,
          width: 620,
        }}
      >
        <div style={{ fontSize: 42, fontWeight: 850, color: colors.text, letterSpacing: -1.2 }}>
          Start with what
          <br />
          needs doing.
        </div>
        <div style={{ fontSize: 20, color: colors.secondary, marginTop: 16, lineHeight: 1.45 }}>
          One field is enough. TodayFlow fills in the date and keeps the task in Today.
        </div>
        <div style={{ marginTop: 34, display: "flex", flexDirection: "column", gap: 18 }}>
          <Step number={1} active={step === 0} done={step > 0}>
            Click <b style={{ margin: "0 4px" }}>+</b> or press <b style={{ margin: "0 4px" }}>⌘N</b>
          </Step>
          <Step number={2} active={step === 1} done={step > 1}>
            Type the task
          </Step>
          <Step number={3} active={step === 2} done={step > 2}>
            Press <b style={{ margin: "0 4px" }}>Add task</b>
          </Step>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          right: 62,
          bottom: 46,
          padding: "10px 15px",
          borderRadius: 999,
          fontSize: 13,
          fontWeight: 700,
          color: colors.green,
          background: "rgba(52,211,153,.10)",
          border: "1px solid rgba(52,211,153,.32)",
        }}
      >
        Real screen recording
      </div>
    </Backdrop>
  );
};

const Cursor: React.FC<{ x: number; y: number; click?: number }> = ({ x, y, click }) => (
  <>
    <svg
      width="24"
      height="28"
      viewBox="0 0 24 28"
      style={{ position: "absolute", left: x, top: y, zIndex: 20, filter: "drop-shadow(0 4px 8px rgba(0,0,0,.45))" }}
    >
      <path d="M2 2 L2 21 L7 16 L11 25 L15 23 L11 14 L19 14 Z" fill="white" stroke="#0b1220" strokeWidth="1.6" />
    </svg>
    {click !== undefined && click > 0 ? (
      <div
        style={{
          position: "absolute",
          left: x - 12,
          top: y - 12,
          width: 48,
          height: 48,
          borderRadius: 24,
          border: "2px solid rgba(96,165,250,.85)",
          opacity: click,
          transform: `scale(${1 + (1 - click) * 1.2})`,
        }}
      />
    ) : null}
  </>
);

const TagsScene: React.FC = () => {
  const frame = useCurrentFrame();
  const pop = interpolate(frame, [35, 55, 120], [0, 1, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const cursorX = interpolate(frame, [20, 55], [420, 280], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const cursorY = interpolate(frame, [20, 55], [430, 176], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <Backdrop>
      <div style={{ position: "absolute", left: 74, top: 44 }}>
        <Chapter index="2" label="Tags" />
      </div>
      <div
        style={{
          position: "absolute",
          left: 84,
          top: 100,
          width: 620,
          height: 551,
          borderRadius: 18,
          overflow: "hidden",
          border: "1px solid rgba(255,255,255,.14)",
          boxShadow: "0 34px 90px rgba(0,0,0,.55)",
        }}
      >
        <Img
          src={staticFile("task-contact.png")}
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
        <div
          style={{
            position: "absolute",
            left: 200,
            top: 163,
            padding: "5px 9px",
            borderRadius: 999,
            background: "rgba(96,165,250,.22)",
            border: "1px solid rgba(96,165,250,.75)",
            color: "#dbeafe",
            fontSize: 14,
            fontWeight: 750,
            opacity: pop,
            transform: `scale(${0.8 + pop * 0.2})`,
          }}
        >
          #Q4
        </div>
      </div>
      <div style={{ position: "absolute", left: 760, top: 130, width: 450 }}>
        <div style={{ fontSize: 44, fontWeight: 850, color: colors.text, letterSpacing: -1.4 }}>
          Tag it once.
          <br />
          Find it everywhere.
        </div>
        <div style={{ fontSize: 20, color: colors.secondary, marginTop: 16, lineHeight: 1.45 }}>
          Tags work on tasks and projects, so the same label can connect a project and its work.
        </div>
        <div style={{ marginTop: 30, display: "flex", flexDirection: "column", gap: 16 }}>
          {[
            "Add tags while capturing a task.",
            "Edit them in the detail view — tasks and projects share the same tag row.",
            "Click the tag icon in the filter row to narrow Today.",
          ].map((line, index) => (
            <div key={line} style={{ display: "flex", gap: 12, alignItems: "flex-start", color: colors.text, fontSize: 19, lineHeight: 1.35 }}>
              <div
                style={{
                  width: 26,
                  height: 26,
                  borderRadius: 13,
                  background: "rgba(96,165,250,.16)",
                  border: "1px solid rgba(96,165,250,.38)",
                  color: colors.accent,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 13,
                  fontWeight: 800,
                  flexShrink: 0,
                }}
              >
                {index + 1}
              </div>
              {line}
            </div>
          ))}
        </div>
      </div>
      <Cursor x={cursorX} y={cursorY} />
      <div
        style={{
          position: "absolute",
          left: 84,
          bottom: 30,
          padding: "9px 14px",
          borderRadius: 999,
          fontSize: 14,
          fontWeight: 700,
          color: colors.text,
          background: "rgba(148,163,184,.10)",
          border: "1px solid rgba(148,163,184,.24)",
        }}
      >
        #launch #Q4 on a task · #launch on the project · filter once
      </div>
    </Backdrop>
  );
};

const EmailScene: React.FC = () => {
  const frame = useCurrentFrame();
  const t = interpolate(frame, [35, 95], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.inOut(Easing.cubic),
  });
  const cursorX = interpolate(t, [0, 1], [435, 905]);
  const cursorY = interpolate(t, [0, 1], [338, 315]);
  const cardX = interpolate(t, [0, 0.7], [0, 26]);
  const cardOpacity = interpolate(t, [0.72, 0.95], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const click = interpolate(frame, [95, 105, 120], [1, 0.3, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const check = interpolate(frame, [100, 116], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <Backdrop>
      <div style={{ position: "absolute", left: 74, top: 44 }}>
        <Chapter index="3" label="Drag & drop" />
      </div>
      <div style={{ position: "absolute", left: 90, top: 120, width: 470 }}>
        <div style={{ fontSize: 42, fontWeight: 850, color: colors.text, letterSpacing: -1.2 }}>
          Drag an email
          <br />
          into Today.
        </div>
        <div style={{ fontSize: 20, color: colors.secondary, marginTop: 14, lineHeight: 1.45 }}>
          The subject becomes the task. The message becomes context.
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 92 + cardX,
          top: 402,
          width: 380,
          padding: 18,
          borderRadius: 16,
          background: colors.surface,
          border: "1px solid rgba(255,255,255,.13)",
          boxShadow: "0 24px 60px rgba(0,0,0,.5)",
          opacity: cardOpacity,
        }}
      >
        <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
          <div
            style={{
              width: 38,
              height: 38,
              borderRadius: 10,
              background: "rgba(96,165,250,.18)",
              border: "1px solid rgba(96,165,250,.35)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 19,
            }}
          >
            ✉
          </div>
          <div>
            <div style={{ fontSize: 17, fontWeight: 750, color: colors.text }}>Q4 roadmap review</div>
            <div style={{ fontSize: 13, color: colors.secondary, marginTop: 2 }}>Demo Team · Today</div>
          </div>
        </div>
        <div style={{ marginTop: 13, fontSize: 14, lineHeight: 1.45, color: "#cbd5e1" }}>
          Here is the roadmap for the Q4 review. Can you take a look?
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          right: 50,
          top: 58,
          width: 300,
          height: 557,
          borderRadius: 20,
          overflow: "hidden",
          boxShadow: "0 34px 90px rgba(0,0,0,.55)",
          border: "1px solid rgba(255,255,255,.14)",
        }}
      >
        <Img
          src={staticFile("today-panel.png")}
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: "rgba(52,211,153,.10)",
            opacity: check,
            border: "2px solid rgba(52,211,153,.65)",
            borderRadius: 20,
          }}
        />
      </div>
      <Cursor x={cursorX} y={cursorY} click={click} />
      <div
        style={{
          position: "absolute",
          right: 58,
          bottom: 60,
          padding: "12px 18px",
          borderRadius: 12,
          fontSize: 16,
          fontWeight: 750,
          color: colors.text,
          background: "rgba(52,211,153,.16)",
          border: "1px solid rgba(52,211,153,.45)",
          opacity: check,
          transform: `translateY(${(1 - check) * 12}px)`,
        }}
      >
        ✓ Task created from the email
      </div>
      <div
        style={{
          position: "absolute",
          left: 90,
          bottom: 46,
          fontSize: 14,
          color: colors.secondary,
        }}
      >
        Works with Mail, Outlook, and any app that can drag a message.
      </div>
    </Backdrop>
  );
};

const FileScene: React.FC = () => {
  return (
    <Backdrop>
      <div style={{ position: "absolute", left: 74, top: 26 }}>
        <Chapter index="3" label="Drag & drop · file" />
      </div>
      <div
        style={{
          position: "absolute",
          left: 80,
          top: 86,
          width: 1120,
          height: 560,
          borderRadius: 18,
          overflow: "hidden",
          border: "1px solid rgba(255,255,255,.14)",
          boxShadow: "0 34px 90px rgba(0,0,0,.55)",
        }}
      >
        <OffthreadVideo
          src={staticFile("use-cases/drag-file-demo.mp4")}
          style={{ width: 1190, height: 560, objectFit: "cover", objectPosition: "left center" }}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 80,
          right: 80,
          bottom: 24,
          display: "flex",
          alignItems: "center",
          gap: 12,
          fontSize: 18,
          color: colors.text,
        }}
      >
        <div
          style={{
            padding: "8px 12px",
            borderRadius: 8,
            background: "rgba(96,165,250,.16)",
            border: "1px solid rgba(96,165,250,.35)",
            color: colors.accent,
            fontWeight: 800,
            fontSize: 13,
            letterSpacing: 1.2,
          }}
        >
          PDF
        </div>
        Drag a file from Finder. It becomes an attachment on the new task.
      </div>
    </Backdrop>
  );
};

const WorkflowScene: React.FC = () => {
  const frame = useCurrentFrame();
  const highlight = interpolate(frame, [120, 150, 210], [0, 1, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <Backdrop>
      <div style={{ position: "absolute", left: 74, top: 20 }}>
        <Chapter index="4" label="Build a workflow" />
      </div>
      <div
        style={{
          position: "absolute",
          left: 180,
          top: 58,
          width: 920,
          height: 648,
          borderRadius: 18,
          overflow: "hidden",
          border: "1px solid rgba(255,255,255,.14)",
          boxShadow: "0 34px 90px rgba(0,0,0,.55)",
        }}
      >
        <OffthreadVideo
          src={staticFile("use-cases/workflow-setup.mp4")}
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 840,
          top: 264,
          width: 258,
          height: 34,
          borderRadius: 10,
          border: "2px solid rgba(96,165,250,.95)",
          boxShadow: "0 0 0 8px rgba(96,165,250,.12)",
          opacity: highlight,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 1112,
          top: 268,
          padding: "7px 10px",
          borderRadius: 8,
          fontSize: 13,
          fontWeight: 750,
          color: colors.accent,
          background: "rgba(7,9,15,.88)",
          border: "1px solid rgba(96,165,250,.42)",
          opacity: highlight,
        }}
      >
        ← On = automatic
      </div>
      <div
        style={{
          position: "absolute",
          left: 80,
          right: 80,
          bottom: 18,
          fontSize: 17,
          color: colors.secondary,
          textAlign: "center",
        }}
      >
        Drag from one tray’s handle to another. The workflow is on when the line appears — there is no Run button.
      </div>
    </Backdrop>
  );
};

const WorkingScene: React.FC = () => {
  const frame = useCurrentFrame();
  const pulse = interpolate(frame, [70, 110, 160], [0, 1, 0.55], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <Backdrop>
      <div style={{ position: "absolute", left: 74, top: 32 }}>
        <Chapter index="5" label="Watch it work" />
      </div>
      <div
        style={{
          position: "absolute",
          left: 104,
          top: 92,
          width: 380,
          height: 705,
          borderRadius: 20,
          overflow: "hidden",
          border: "1px solid rgba(255,255,255,.14)",
          boxShadow: "0 34px 90px rgba(0,0,0,.55)",
        }}
      >
        <OffthreadVideo
          src={staticFile("use-cases/workflow-complete.mp4")}
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
        <div
          style={{
            position: "absolute",
            left: 12,
            top: 292,
            width: 172,
            height: 62,
            borderRadius: 14,
            border: "2px solid rgba(52,211,153,.95)",
            boxShadow: "0 0 0 8px rgba(52,211,153,.12)",
            zIndex: 5,
            opacity: pulse,
          }}
        />
      </div>
      <div style={{ position: "absolute", left: 560, top: 120, width: 650 }}>
        <div style={{ fontSize: 44, fontWeight: 850, color: colors.text, letterSpacing: -1.4 }}>
          Complete it.
          <br />
          It moves.
        </div>
        <div style={{ fontSize: 20, color: colors.secondary, marginTop: 14, lineHeight: 1.45 }}>
          The task leaves Inbox and appears in Done without a single click on a Run button.
        </div>
        <div style={{ display: "flex", gap: 16, marginTop: 34 }}>
          {[
            { label: "INBOX", before: "2", after: "1", color: colors.accent },
            { label: "DONE", before: "0", after: "1", color: colors.green },
          ].map((stat) => (
            <div
              key={stat.label}
              style={{
                flex: 1,
                padding: "18px 20px",
                borderRadius: 16,
                background: "rgba(148,163,184,.08)",
                border: "1px solid rgba(148,163,184,.20)",
              }}
            >
              <div style={{ fontSize: 12, fontWeight: 800, letterSpacing: 2, color: stat.color }}>
                {stat.label}
              </div>
              <div style={{ display: "flex", alignItems: "baseline", gap: 10, marginTop: 8 }}>
                <div style={{ fontSize: 34, fontWeight: 850, color: colors.secondary, textDecoration: "line-through", opacity: 0.6 }}>
                  {stat.before}
                </div>
                <div style={{ fontSize: 22, color: colors.secondary }}>→</div>
                <div style={{ fontSize: 42, fontWeight: 900, color: stat.color }}>{stat.after}</div>
              </div>
            </div>
          ))}
        </div>
        <div
          style={{
            marginTop: 26,
            display: "flex",
            alignItems: "center",
            gap: 12,
            padding: "14px 18px",
            borderRadius: 12,
            background: "rgba(52,211,153,.10)",
            border: "1px solid rgba(52,211,153,.32)",
            fontSize: 17,
            color: colors.text,
          }}
        >
          <div
            style={{
              width: 26,
              height: 26,
              borderRadius: 13,
              background: colors.green,
              color: "#052e1b",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontWeight: 900,
            }}
          >
            ✓
          </div>
          Workflow on. Task completed. Tray updated.
        </div>
      </div>
    </Backdrop>
  );
};

const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 18, stiffness: 80 } });
  return (
    <Backdrop>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", textAlign: "center" }}>
        <div style={{ fontSize: 32, fontWeight: 800, color: colors.accent, letterSpacing: 3, textTransform: "uppercase" }}>
          No Run button
        </div>
        <div style={{ fontSize: 76, fontWeight: 900, color: colors.text, letterSpacing: -3, marginTop: 14, opacity: enter }}>
          On means automatic.
        </div>
        <div style={{ fontSize: 25, color: colors.secondary, marginTop: 18 }}>
          Turn a workflow on. Complete a task. Watch the tray update.
        </div>
        <div
          style={{
            marginTop: 40,
            padding: "12px 20px",
            borderRadius: 999,
            background: "rgba(96,165,250,.12)",
            border: "1px solid rgba(96,165,250,.35)",
            color: colors.text,
            fontSize: 17,
            fontWeight: 700,
          }}
        >
          TodayFlow → Watch Video Walkthrough
        </div>
      </AbsoluteFill>
    </Backdrop>
  );
};

export const TodayFlowUseCases: React.FC = () => {
  return (
    <AbsoluteFill style={{ fontFamily: font, background: colors.background }}>
      <Sequence durationInFrames={90}>
        <Scene duration={90}>
          <Title />
        </Scene>
      </Sequence>
      <Sequence from={90} durationInFrames={260}>
        <Scene duration={260}>
          <CreateTaskScene />
        </Scene>
      </Sequence>
      <Sequence from={350} durationInFrames={150}>
        <Scene duration={150}>
          <TagsScene />
        </Scene>
      </Sequence>
      <Sequence from={500} durationInFrames={150}>
        <Scene duration={150}>
          <EmailScene />
        </Scene>
      </Sequence>
      <Sequence from={650} durationInFrames={210}>
        <Scene duration={210}>
          <FileScene />
        </Scene>
      </Sequence>
      <Sequence from={860} durationInFrames={240}>
        <Scene duration={240}>
          <WorkflowScene />
        </Scene>
      </Sequence>
      <Sequence from={1100} durationInFrames={240}>
        <Scene duration={240}>
          <WorkingScene />
        </Scene>
      </Sequence>
      <Sequence from={1340} durationInFrames={90}>
        <Scene duration={90}>
          <Outro />
        </Scene>
      </Sequence>
    </AbsoluteFill>
  );
};
