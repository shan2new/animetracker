import { LegalDocument, legalMetadata } from '../legal-document';
export const metadata = legalMetadata('support');
export default function Page() {
  return <LegalDocument kind="support" />;
}
