import { LegalDocument, legalMetadata } from '../legal-document';
export const metadata = legalMetadata('terms');
export default function Page() {
  return <LegalDocument kind="terms" />;
}
