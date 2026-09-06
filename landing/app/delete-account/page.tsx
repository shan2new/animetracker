import { LegalDocument, legalMetadata } from '../legal-document';
export const metadata = legalMetadata('delete-account');
export default function Page() {
  return <LegalDocument kind="delete-account" />;
}
