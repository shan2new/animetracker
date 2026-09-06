import { LegalDocument, legalMetadata } from '../legal-document';
export const metadata = legalMetadata('privacy');
export default function Page() {
  return <LegalDocument kind="privacy" />;
}
