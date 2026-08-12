export const dynamic = "force-static";

export function GET() {
  return Response.json({
    applinks: {
      details: [
        {
          appIDs: ["5TXL5P4663.com.nexro.Tsundoku"],
          components: [{ "/": "/c/*", comment: "Open shared Casts in StashCast" }],
        },
      ],
    },
  });
}
