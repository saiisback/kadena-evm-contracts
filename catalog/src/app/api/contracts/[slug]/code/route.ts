import { NextResponse } from "next/server";
import { promises as fs } from "node:fs";
import path from "node:path";

import { getContractBySlug } from "@/data/contracts";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  const contract = getContractBySlug(slug);

  if (!contract) {
    return NextResponse.json({ error: "Contract not found" }, { status: 404 });
  }

  try {
    const absolutePath = path.resolve(process.cwd(), contract.path);
    const code = await fs.readFile(absolutePath, "utf-8");

    return NextResponse.json({
      slug: contract.slug,
      name: contract.name,
      code,
      contractName: contract.contractName,
      path: contract.path,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error: "Unable to read contract source",
        details: error instanceof Error ? error.message : String(error),
      },
      { status: 500 },
    );
  }
}


