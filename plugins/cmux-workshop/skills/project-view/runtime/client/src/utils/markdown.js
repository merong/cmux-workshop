import { marked } from "marked";

marked.setOptions({ breaks: true });

/**
 * 잘린 마크다운 텍스트의 열린 구문을 닫고, 인라인 테이블을 복원하여
 * 렌더링이 깨지지 않도록 보정.
 */
export function sanitizeMarkdown(text) {
  if (!text) return text;

  let result = text;

  // 0. 인라인 테이블 복원 — 줄바꿈 없이 한 줄에 합쳐진 테이블 감지 및 분리
  result = fixInlineTables(result);

  // 1. 코드 펜스 (```) — 홀수 개면 마지막에 닫기
  const fenceCount = (result.match(/^```/gm) || []).length;
  if (fenceCount % 2 !== 0) {
    result += "\n```";
  }

  // 2. 인라인 코드 (`) — 코드 펜스 블록 밖에서 홀수면 닫기
  let insideFence = false;
  let inlineBackticks = 0;
  for (const line of result.split("\n")) {
    if (/^```/.test(line)) {
      insideFence = !insideFence;
      continue;
    }
    if (!insideFence) {
      let i = 0;
      while (i < line.length) {
        if (line[i] === "`") {
          while (i < line.length && line[i] === "`") i++;
          inlineBackticks++;
        } else {
          i++;
        }
      }
    }
  }
  if (inlineBackticks % 2 !== 0) {
    result += "`";
  }

  // 3. 볼드/이탤릭/취소선 — 코드 블록 밖에서 열린 마커 닫기
  const stripped = result
    .replace(/```[\s\S]*?```/g, "")
    .replace(/`[^`]*`/g, "");

  for (const marker of ["~~", "**", "__", "*", "_"]) {
    const escaped = marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const matches = stripped.match(new RegExp(escaped, "g")) || [];
    if (matches.length % 2 !== 0) {
      result += marker;
    }
  }

  // 4. 잘린 링크/이미지 구문 제거
  result = result.replace(/!?\[[^\]]*$/, "");

  // 5. 잘린 테이블 행 — 마지막 줄이 | 로 시작하지만 | 로 끝나지 않으면 닫기
  const lastLine = result.split("\n").pop();
  if (lastLine && lastLine.trimStart().startsWith("|") && !lastLine.trimEnd().endsWith("|")) {
    result += " |";
  }

  return result;
}

/**
 * 줄바꿈 없이 한 줄에 합쳐진 마크다운 테이블을 감지하여
 * 각 행 사이에 줄바꿈을 삽입.
 *
 * 입력 예:  "요약: | A | B | |---|---| | 1 | 2 |"
 * 출력 예:  "요약:\n\n| A | B |\n|---|---|\n| 1 | 2 |"
 */
function fixInlineTables(text) {
  // 테이블 구분자 패턴 감지: |---| 또는 |:---:| 등
  const sepPattern = /(\|\s*[-:]+\s*)+\|/;
  const sepMatch = text.match(sepPattern);
  if (!sepMatch) return text;

  // 이미 줄바꿈으로 분리된 테이블이면 스킵
  const sepIdx = text.indexOf(sepMatch[0]);
  const charBefore = sepIdx > 0 ? text[sepIdx - 1] : "\n";
  if (charBefore === "\n") return text;

  // 구분자에서 열 수 계산
  const sep = sepMatch[0];
  const colCount = (sep.match(/\|/g) || []).length - 1;
  if (colCount < 1) return text;
  const pipesPerRow = colCount + 1;

  // 테이블 시작 위치 찾기: 구분자 앞으로 pipesPerRow개 | 를 거슬러 올라감
  let headerStart = sepIdx;
  let pipesBefore = 0;
  for (let i = sepIdx - 1; i >= 0; i--) {
    if (text[i] === "|") {
      pipesBefore++;
      if (pipesBefore === pipesPerRow) {
        headerStart = i;
        break;
      }
    }
  }

  const before = text.substring(0, headerStart).trimEnd();
  const tableRegion = text.substring(headerStart);

  // 테이블 영역에서 pipesPerRow 단위로 행 분리
  let pipes = 0;
  let fixed = "";
  let i = 0;
  while (i < tableRegion.length) {
    const ch = tableRegion[i];
    if (ch === "|") {
      pipes++;
      fixed += "|";
      if (pipes % pipesPerRow === 0) {
        // 행 끝 — 다음 행이 있으면 줄바꿈 삽입
        let j = i + 1;
        while (j < tableRegion.length && tableRegion[j] === " ") j++;
        if (j < tableRegion.length) {
          if (tableRegion[j] === "|") {
            fixed += "\n";
            i = j;
            continue;
          } else {
            // 테이블 끝, 나머지 텍스트 추가
            fixed += "\n\n" + tableRegion.substring(j).trimStart();
            i = tableRegion.length;
            break;
          }
        }
      }
    } else {
      fixed += ch;
    }
    i++;
  }

  return (before ? before + "\n\n" : "") + fixed;
}

export function renderMarkdown(text) {
  try {
    return marked.parse(sanitizeMarkdown(text));
  } catch {
    return text;
  }
}
